//
//  FileProxy.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation
import os.log

@available(iOS 10.0, macOS 10.13, *)
private let log = OSLog(subsystem: "ink.codes.fileproxy", category: "fs")

public final class FileProxy: NSObject {

  public let identifier: String
  public let maxBytes: Int
  public weak var delegate: FileProxyDelegate?
  private var _bgSession: URLSession?

  public init(
    identifier: String = "ink.codes.fileproxy",
    maxBytes: Int = 256 * 1024 * 1024,
    delegate: FileProxyDelegate? = nil,
    backgroundSession: URLSession? = nil
  ) {
    self.identifier = identifier
    self.maxBytes = maxBytes
    self.delegate = delegate
    self._bgSession = backgroundSession
  }
  
  fileprivate var isInvalidated = false
  
  deinit {
    precondition(isInvalidated)
  }

  public var backgroundCompletionHandler: (() -> Void)?

}

// MARK: - URLSessionDelegate

extension FileProxy: URLSessionDelegate {
  
  private func dispatch() {
    DispatchQueue.main.async { [weak self] in
      self?.backgroundCompletionHandler?()
      self?.backgroundCompletionHandler = nil
    }
  }

  #if(iOS)
  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    os_log("session did finish", log: log, type: .debug)
    guard !isInvalidated else {
      return
    }
    dispatch()
  }
  #endif
  
  public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    os_log("session did become invalid", log: log, type: .debug)
    dispatch()
  }
  
}

// MARK: - URLSessionTaskDelegate

extension FileProxy: URLSessionTaskDelegate {

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard !isInvalidated else {
      return
    }
    let url = task.originalRequest?.url
    delegate?.proxy(self, url: url, didCompleteWithError: error)
  }
  
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    let url = task.originalRequest?.url
    delegate?.proxy(
      self, url: url!, didReceive: challenge,
      completionHandler: completionHandler
    )
  }

}

// MARK: - URLSessionDownloadDelegate

extension FileProxy: URLSessionDownloadDelegate {
  
  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64) {
    guard let url = downloadTask.originalRequest?.url else {
      return
    }
    delegate?.proxy(
      self, url: url, didWriteData: bytesWritten,
      totalBytesWritten: totalBytesWritten,
      totalBytesExpectedToWrite: totalBytesExpectedToWrite
    )
  }
  
  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL) {
    guard
      let origin = downloadTask.originalRequest?.url,
      let savedURL = FileLocator(identifier: identifier,
        url: origin)?.localURL else {
      delegate?.proxy(self, url: nil, didCompleteWithError: nil)
      return
    }

    guard let res = downloadTask.response as? HTTPURLResponse  else {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("no reponse: %{public}@", log: log, type: .debug,
               downloadTask as CVarArg)
      }
      return
    }

    guard (200...299).contains(res.statusCode) else {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("unexpected response: %i", log: log, res.statusCode)
      }
      delegate?.proxy(self, url: origin,
        failedToDownloadWith: FileProxyError.http(res.statusCode))
      return
    }

    if #available(iOS 10.0, macOS 10.13, *) {
      os_log("""
        moving item: {
          %{public}@,
          %{public}@,
          %{public}@
        }
        """, log: log, type: .debug,
        origin as CVarArg,
        downloadTask as CVarArg,
        savedURL as CVarArg
      )
    }

    do {
      try FileManager.default.moveItem(at: location, to: savedURL)

      delegate?.proxy(self, url: origin, successfullyDownloadedTo: savedURL)
    } catch {
      delegate?.proxy(self, url: origin, failedToDownloadWith: error)
      return
    }

  }

}

// MARK: - FileProxying

extension FileProxy: FileProxying {
  
  public func invalidate(finishing: Bool = true) {
    if finishing {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("finishing and invalidating", log: log, type: .debug)
      }
      _bgSession?.finishTasksAndInvalidate()
    } else {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("invalidating and cancelling", log: log, type: .debug)
      }
      _bgSession?.invalidateAndCancel()
    }
    isInvalidated = true
  }
  
  private func makeBackgroundSession() -> URLSession {
    precondition(!isInvalidated)
    let conf = URLSessionConfiguration.background(withIdentifier: identifier)
    conf.isDiscretionary = true
    return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
  }

  private var bgSession: URLSession {
    set { _bgSession = newValue }

    get {
      guard let s = _bgSession else {
        _bgSession = makeBackgroundSession()
        return _bgSession!
      }
      return s
    }
  }

  func totalBytes() throws -> Int {
    do {
      let dir = try FileLocator.targetDirectory(identifier: identifier)
      let urls = try FileManager.default.contentsOfDirectory(at: dir,
        includingPropertiesForKeys: [.fileSizeKey])
      return try urls.reduce(0, { acc, url in
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
          throw FileProxyError.fileSizeRequired
        }
        return acc + fileSize
      })
    } catch {
      throw error
    }
  }

  /// Throws if we ran out of file space.
  private func checkSize() throws {
    let bytes = try totalBytes()
    let space = maxBytes - bytes
    guard space > 0 else {
      throw FileProxyError.maxBytesExceeded(space)
    }
  }

  @discardableResult
  public func url(
    for url: URL,
    with configuration: DownloadTaskConfiguration? = nil
  ) throws -> URL {
    dispatchPrecondition(condition: .notOnQueue(.main))
    
    guard let localURL = FileLocator(identifier: identifier, url: url)?.localURL else {
      throw FileProxyError.invalidURL(url)
    }

    if #available(iOS 10.0, macOS 10.13, *) {
      os_log("""
        checking: {
          %{public}@,
          %{public}@
        }
        """, log: log, type: .debug, url as CVarArg, localURL as CVarArg)
    }

    do {
      if try localURL.checkResourceIsReachable() {
        if #available(iOS 10.0, macOS 10.13, *) {
          os_log("reachable: %{public}@", log: log, type: .debug,
                 localURL as CVarArg)
        }
        return localURL
      }
    } catch {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("not reachable: %{public}@", log: log, type: .debug,
               localURL as CVarArg)
      }
    }

    try checkSize()

    let session = self.bgSession

    func go() {
      let task = session.downloadTask(with: url)

      if #available(iOS 11.0, macOS 10.13, *) {
        if let s = configuration?.countOfBytesClientExpectsToSend {
          task.countOfBytesClientExpectsToSend = s
        }
        if let r = configuration?.countOfBytesClientExpectsToReceive {
          task.countOfBytesClientExpectsToReceive = r
        }
        if let d = configuration?.earliestBeginDate {
          task.earliestBeginDate = d
        }
      }

      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("""
          downloading: {
            %{public}@,
            %{public}@
          }
          """, log: log, type: .debug, url as CVarArg, task as CVarArg)
      }

      task.resume()
    }

    // Guarding against URLs already in-flight.
    session.getTasksWithCompletionHandler { _, _, tasks in
      guard !tasks.isEmpty else {
        return go()
      }

      guard let task = tasks.first (where:
        { $0.originalRequest?.url == url }
      ) else {
        return go()
      }

      if #available(iOS 11.0, macOS 10.13, *) {
        os_log("""
          in-flight: {
            %{public}@,
            %{public}@",
          }
          """, log: log, type: .debug,
               url as CVarArg, task.progress as CVarArg)
      }
    }

    return url
  }
  
  @discardableResult
  public func url(for url: URL) throws -> URL {
    return try self.url(for: url, with: nil)
  }
}
