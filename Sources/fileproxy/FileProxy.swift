//
//  FileProxy.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation
import os.log

@available(iOS 10.0, macOS 10.13, *)
private let log = OSLog(subsystem: "ink.codes.fileproxy", category: "files")

public final class FileProxy: NSObject {

  typealias SessionIdentifier = String

  public let identifier: String
  public let maxBytes: Int
  public weak var delegate: FileProxyDelegate?

  private var sessions = [SessionIdentifier: URLSession]()
  private var handlers = [SessionIdentifier: (() -> Void)]()

  private var current: SessionIdentifier?

  public init(
    identifier: String = "ink.codes.fileproxy",
    maxBytes: Int = 256 * 1024 * 1024,
    delegate: FileProxyDelegate? = nil
  ) {
    if #available(iOS 10.0, macOS 10.13, *) {
      os_log("init: %{public}@", log: log, type: .debug, identifier)
    }
    self.identifier = identifier
    self.maxBytes = maxBytes
    self.delegate = delegate
  }

  fileprivate var isInvalidated = false

  deinit {
    precondition(isInvalidated)
  }

  private func makeBackgroundSession(identifier: SessionIdentifier) -> URLSession {
    precondition(!isInvalidated)
    if #available(iOS 10.0, macOS 10.13, *) {
      os_log("creating a new session: %{public}@", log: log, type: .debug,
             identifier as CVarArg)
    }
    let conf = URLSessionConfiguration.background(withIdentifier: identifier)
    conf.isDiscretionary = true
    return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
  }

}

// MARK: - URLSessionDelegate

extension FileProxy: URLSessionDelegate {

  private func completeSession(matching identifier: SessionIdentifier) {
    if #available(iOS 11.0, macOS 10.13, *) {
      os_log("completing session: %{public}@",
             log: log, type: .debug, identifier)
    }

    guard let cb = handlers.removeValue(forKey: identifier) else {
      if #available(iOS 11.0, macOS 10.13, *) {
        os_log("no handler: %{public}@", log: log, type: .debug, identifier)
      }
      return
    }

    cb()

    precondition(sessions.removeValue(forKey: identifier) != nil)
  }

  #if os(iOS)

  public func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
  ) {
    if #available(iOS 11.0, macOS 10.13, *) {
      os_log("session did finish events: %{public}@",
             log: log, type: .debug, session.configuration.identifier!)
    }

    guard let sid = session.configuration.identifier else {
      if #available(iOS 11.0, macOS 10.13, *) {
        os_log("invalidating session", log: log, type: .debug)
      }
      session.invalidateAndCancel()
      return
    }

    completeSession(matching: sid)
  }

  #endif

  public func urlSession(
    _ session: URLSession,
    didBecomeInvalidWithError error: Error?
  ) {
    if #available(iOS 11.0, macOS 10.13, *) {
      if let er = error {
        os_log("invalid session with error: %{public}@",
               log: log, type: .error, er as CVarArg)
      } else {
        os_log("invalid session", log: log, type: .error)
      }
    }
    guard let sid = session.configuration.identifier else {
      fatalError("missing session identifier")
    }
    completeSession(matching: sid)
    isInvalidated = true
  }

  // Handling authentication challenges on the task level, not here, on the
  // session level.

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

  public func handleEventsForBackgroundURLSession(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    let _: URLSession = {
      guard let id = current, let s = sessions[id] else {
        let newSession = makeBackgroundSession(identifier: identifier)
        sessions[identifier] = newSession
        return newSession
      }
      return s
    }()

    guard handlers.removeValue(forKey: identifier) == nil else {
      fatalError("unexpectedly found existing handler: \(identifier)")
    }

    handlers[identifier] = completionHandler
  }

  public func invalidate(finishing: Bool = true) {
    if finishing {
      for session in sessions.values {
        if #available(iOS 10.0, macOS 10.13, *) {
          os_log("finishing and invalidating: %{public}@",
                 log: log, type: .debug, session.configuration.identifier!)
        }
        session.finishTasksAndInvalidate()
      }
    } else {
      for session in sessions.values {
        if #available(iOS 10.0, macOS 10.13, *) {
          os_log("invalidating and cancelling: %{public}@",
                 log: log, type: .debug, session.configuration.identifier!)
        }
        session.invalidateAndCancel()
      }
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
  
  private func tasks(
    matching url: URL,
    tasksBlock: @escaping ([URLSessionDownloadTask]
  ) -> Void) {
    func find(sessions: [URLSession], index: Int, found: [URLSessionDownloadTask]) {
      guard !sessions.isEmpty, index >= 0 else {
        return tasksBlock(found)
      }
      
      let session = sessions[index]
      
      session.getTasksWithCompletionHandler { _, _, tasks in
        find(sessions: sessions, index: index - 1, found:
          found + tasks.filter { $0.originalRequest?.url == url }
        )
      }
    }
    
    let last = max(0, sessions.count - 1)
    find(sessions: Array(sessions.values), index: last, found: [])
  }
  
  public func cancelDownloads(matching url: URL) {
    tasks(matching: url) { tasks in
      for task in tasks {
        task.cancel()
      }
    }
  }

  public func removeFile(matching url: URL) -> URL? {
    guard let localURL = FileLocator(
      identifier: identifier, url: url)?.localURL else {
      return nil
    }
    
    do {
      try FileManager.default.removeItem(at: localURL)
    } catch {
      return nil
    }
    
    return localURL
  }
  
  private func hasTasks(matching url: URL, hasBlock: @escaping (Bool) -> Void) {
    tasks(matching: url) { tasks in
      hasBlock(!tasks.isEmpty)
    }
  }

  @discardableResult
  public func url(
    for url: URL,
    with configuration: DownloadTaskConfiguration? = nil
  ) throws -> URL {
    // dispatchPrecondition(condition: .notOnQueue(.main))

    guard let localURL = FileLocator(
      identifier: identifier, url: url)?.localURL else {
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

    func go() {
      let session: URLSession = {
        guard let id = current, let s = sessions[id] else {
          let newID = "\(identifier)-\(UUID().uuidString)"
          let newSession = makeBackgroundSession(identifier: newID)
          sessions[newID] = newSession
          current = newID
          return newSession
        }
        return s
      }()

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
    hasTasks(matching: url) { yes in
      if !yes { go() }
    }

    return url
  }

  @discardableResult
  public func url(for url: URL) throws -> URL {
    return try self.url(for: url, with: nil)
  }
}
