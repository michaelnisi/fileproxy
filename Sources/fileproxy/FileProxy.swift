//
//  FileProxy.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation
import os.log

private let log = OSLog(subsystem: "ink.codes.fileproxy", category: "files")

public final class FileProxy: NSObject {

  public let identifier: String
  public let maxBytes: Int

  /// The file proxy delegate receives combined events of all background
  /// sessions currently managed by this file proxy.
  ///
  /// These callbacks execute in order, but interspersed, on the respective
  /// session delegate queues. Depending on the number of sessions, this can
  /// get hairy.
  public weak var delegate: FileProxyDelegate?

  /// Identifies sessions, equivalent to `URLSessionConfiguration.identifier`.
  private typealias SessionIdentifier = String

  /// Wraps our url session, adding context for letting us know if the session
  /// was created to handle events for a background url session. A `.transient`
  /// session can become `.background` at the next launch.
  ///
  /// Notice the difference to `URLSessionConfiguration.background`, all our
  /// url sessions are background url sessions.
  private enum Session {
    case background(SessionIdentifier, URLSession, () -> Void)
    case transient(SessionIdentifier, URLSession)

    var configuration: URLSessionConfiguration {
      switch self {
      case .background(_, let s, _):
        return s.configuration
      case .transient(_, let s):
        return s.configuration
      }
    }

    func downloadTask(with url: URL) -> URLSessionDownloadTask {
      switch self {
      case .background(_, let s, _):
        return s.downloadTask(with: url)
      case .transient(_, let s):
        return s.downloadTask(with: url)
      }
    }
  }

  /// Synchronizes access to sessions, handlers, and our invalidation flag.
  private let sQueue: DispatchQueue

  /// Stores our sessions.
  private var _sessionsByIds: [SessionIdentifier: Session]!

  /// Creates a new file proxy.
  ///
  /// - Parameters:
  ///   - identifier: The name of this file proxy.
  ///   - maxBytes: The maximum bytes to consume for local storage.
  ///   - delegate: The file proxy delegate.
  public init(
    identifier: String = "ink.codes.fileproxy",
    maxBytes: Int = 256 * 1024 * 1024,
    delegate: FileProxyDelegate? = nil
  ) {
    os_log("initializing: %{public}@", log: log, type: .debug, identifier)

    self.identifier = identifier
    self.maxBytes = maxBytes
    self.delegate = delegate

    self.sQueue = DispatchQueue(label: identifier)
  }

  private var _isInvalid: Bool = true

  /// After this is `true`, this object is trash and cannot be used any longer.
  private var isInvalid: Bool {
    get { return sQueue.sync { _isInvalid } }
    set { sQueue.sync { _isInvalid = newValue } }
  }

  deinit {
    precondition(_isInvalid)
  }

}

// MARK: - Accessing Sessions

extension FileProxy {

  private func makeSession(
    identifier: SessionIdentifier,
    completionBlock: (() -> Void)? = nil
  ) -> Session {
    let conf = URLSessionConfiguration.background(withIdentifier: identifier)

    conf.isDiscretionary = delegate?.isDiscretionary ?? true
    conf.allowsCellularAccess = delegate?.allowsCellularAccess ?? false

    os_log("""
      creating session: (
        identifier: %{public}@,
        isDiscretionary: %i,
        allowsCellularAccess: %i
      )
      """, log: log, type: .debug,
           identifier, conf.isDiscretionary, conf.allowsCellularAccess)

    let s = URLSession(configuration: conf, delegate: self, delegateQueue: nil)

    guard let cb = completionBlock else {
      return .transient(identifier, s)
    }

    return .background(identifier, s, cb)
  }

  /// Removes the session matching `identifier`.
  @discardableResult
  private func removeSession(matching identifier: SessionIdentifier) -> Session? {
    return sQueue.sync {
      guard let session = _sessionsByIds.removeValue(forKey: identifier) else {
        return nil
      }

      switch session {
      case .background(let id, let s, let completionBlock):
        os_log("invalidating background session: %{public}@", log: log, id)
        s.invalidateAndCancel()
        completionBlock()
      case .transient(let id, let s):
        os_log("invalidating transient session: %{public}@", log: log, id)
        s.invalidateAndCancel()
      }

      return session
    }
  }

  /// Adds `session` for `identifier`.
  ///
  /// Adding an existing session is a mistake.
  private func addSession(_ session: Session, identifier: SessionIdentifier) {
    sQueue.sync {
      precondition(_sessionsByIds[identifier] == nil)
      _sessionsByIds[identifier] = session
    }
  }

  /// Returns all our URL sessions.
  private var urlSessions: [URLSession] {
    return sQueue.sync {
      _sessionsByIds.map {
        switch $0.value {
        case .background(_, let s, _):
          return s
        case .transient(_, let s):
          return s
        }
      }
    }
  }

  private var sessions: [Session] {
    return sQueue.sync {
      Array(_sessionsByIds.values)
    }
  }

  /// Finds download tasks matching `url` in `sessions`.
  private static func tasks(
    in sessions: [URLSession],
    matching url: URL,
    completion: @escaping ([URLSessionDownloadTask]) -> Void)
  {
    func find(_ sessions: [URLSession], _ acc: [URLSessionDownloadTask] = []) {
      guard let session = sessions.first else {
        completion(acc)
        return
      }

      session.getTasksWithCompletionHandler { _, _, tasks in
        find(Array(sessions.dropFirst()), acc + tasks.filter {
          $0.originalRequest?.url == url
        })
      }
    }

    find(sessions)
  }

  /// Finds a sessions `session` to download `url`, snooping for unused session
  /// while at it.
  ///
  /// - Parameters:
  ///   - sessions: The sessions to scan.
  ///   - url: The URL to download with one of the sessions.
  ///   - sessionsBlock: The block to execute with the result.
  ///   - identifier: The identifier of the suggested session to use.
  ///   - unused: Identifiers of currently unused sessions.
  ///   - skip: `true` if the URL is already being downloaded by another task.
  ///
  /// All in one loop for effective monitoring and maximum control. With the
  /// current settings, in most cases, we end up using one or two sessions.
  private static func findSession(
    in sessions: [Session],
    for url: URL,
    sessionBlock: @escaping (
      _ identifier: SessionIdentifier?,
      _ unused: [SessionIdentifier],
      _ skip: Bool
    ) -> Void
  ) {
    os_log("finding in %i sessions", log: log, type: .debug, sessions.count)

    struct Acc {
      let good: SessionIdentifier?
      let unused: [SessionIdentifier]
      let skip: Bool
    }

    func find(
      _ sessions: [Session],
      _ acc: Acc = Acc(good: nil, unused: [], skip: false)
    ) {
      guard let session = sessions.first else {
        os_log("found: %{public}@", log: log, type: .debug, String(describing: acc))
        sessionBlock(acc.good, acc.unused, acc.skip)
        return
      }

      switch session {
      case .background:
        find(Array(sessions.dropFirst()), acc)
      case .transient(let id, let s):
        s.getTasksWithCompletionHandler { _, _, tasks in
          // The URL should be skipped if we find a matching task in-flight.
          guard !tasks.contains(where: { $0.originalRequest?.url == url }) else {
            find(
              Array(sessions.dropFirst()),
              Acc(good: acc.good, unused: acc.unused, skip: true)
            )
            return
          }

          // The session should not exceed the maximum number of tasks.
          // Relatively high maxmimum, for Apple documentation recommending
          // ideally one session per app.
          guard tasks.count < 128 else {
            find(Array(sessions.dropFirst()), acc)
            return
          }

          // If we have already found a good session, we mark the remaining
          // sessions unused if they have no tasks.
          guard acc.good == nil else {
            find(
              Array(sessions.dropFirst()),
              tasks.count > 0
                ? acc :
                Acc(good: acc.good, unused: acc.unused + [id], skip: acc.skip)
            )
            return
          }

          // That’s a good one.
          find(
            Array(sessions.dropFirst()),
            Acc(good: id, unused: acc.unused, skip: acc.skip)
          )
        }
      }
    }

    find(sessions)
  }

  /// Selects the optimal session for downloading `url`, creating and adding a
  /// new one if appropriate, or `nil` if downloading that URL should be
  /// dismissed.
  ///
  /// While iterating our current sessions and tasks, this method also cleans
  /// up, safely removing sessions not longer needed.
  private func selectSession(
    for url: URL,
    sessionBlock: @escaping (Session?) -> Void) {
    FileProxy.findSession(in: sessions, for: url) { identifier, unused, skip in
      for trash in unused {
        self.removeSession(matching: trash)
      }

      guard !skip else {
        return sessionBlock(nil)
      }

      guard let id = identifier else {
        let newId = self.makeSessionIdentifier()
        let newSession = self.makeSession(identifier: newId)
        self.addSession(newSession, identifier: newId)
        return sessionBlock(newSession)
      }

      sessionBlock(self.session(matching: id))
    }
  }

  private func hasSession(matching identifier: SessionIdentifier) -> Bool {
    return sQueue.sync {
      _sessionsByIds[identifier] != nil
    }
  }

  private func session(matching identifier: SessionIdentifier) -> Session? {
    return sQueue.sync {
      _sessionsByIds[identifier]
    }
  }

}

// MARK: - URLSessionDelegate

extension FileProxy: URLSessionDelegate {

  #if os(iOS)

  public func urlSessionDidFinishEvents(
    forBackgroundURLSession session: URLSession
  ) {
    precondition(!isInvalid)

    os_log("session did finish events: %{public}@",
           log: log, type: .debug, session.configuration.identifier!)

    guard let identifier = session.configuration.identifier else {
      os_log("ignoring unidentified session", log: log)
      return
    }

    removeSession(matching: identifier)
  }

  #endif

  public func urlSession(
    _ session: URLSession,
    didBecomeInvalidWithError error: Error?
  ) {
    precondition(!isInvalid)

    if let er = error {
      os_log("invalid session with error: %{public}@",
             log: log, type: .error, er as CVarArg)
    } else {
      os_log("invalid session", log: log, type: .error)
    }

    guard let identifier = session.configuration.identifier else {
      os_log("ignoring unidentified session", log: log)
      return
    }
    
    removeSession(matching: identifier)
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
    precondition(!isInvalid)

    let url = task.originalRequest?.url
    delegate?.proxy(self, url: url, didCompleteWithError: error)
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    precondition(!isInvalid)

    let url = task.originalRequest?.url

    delegate?.proxy(
      self, url: url!, didReceive: challenge,
      completionHandler: completionHandler
    )
  }

}

// MARK: - URLSessionDownloadDelegate

extension FileProxy: URLSessionDownloadDelegate {

  private var allowsCellularAccess: Bool {
    return delegate?.allowsCellularAccess ?? false
  }
  
  private var isDiscretionary: Bool {
    return delegate?.isDiscretionary ?? true
  }

  /// Returns `true` if the session doesn’t allow cellular access or, for
  /// sessions allowing cellular access, it returns `true` if the file proxy
  /// allows cellular access.
  ///
  /// In other words, cellular sessions can be blocked by the delegate.
  private func checkSession(configuration: URLSessionConfiguration) -> Bool {
    precondition(hasSession(matching: configuration.identifier!))
    
    guard configuration.allowsCellularAccess else {
      return true
    }
    
    return allowsCellularAccess
  }

  public func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64) {
    precondition(!isInvalid)

    guard let url = downloadTask.originalRequest?.url else {
      return
    }
    
    guard checkSession(configuration: session.configuration) else {
      if let identifier = session.configuration.identifier {
        removeSession(matching: identifier)
      }

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
    precondition(!isInvalid)

    guard
      let origin = downloadTask.originalRequest?.url,
      let locator = FileLocator(identifier: identifier, url: origin),
      let savedURL = locator.localURL else {
      delegate?.proxy(self, url: nil, didCompleteWithError: nil)
      return
    }

    guard let res = downloadTask.response as? HTTPURLResponse  else {
      os_log("no reponse: %{public}@",
             log: log, type: .debug, downloadTask as CVarArg)
      return
    }

    guard (200...299).contains(res.statusCode) else {
      os_log("unexpected response: (%i, %{public}@)",
             log: log, res.statusCode, origin as CVarArg)

      delegate?.proxy(self, url: origin,
        failedToDownloadWith: FileProxyError.http(res.statusCode))
      return
    }

    os_log("""
      moving item: (
        %{public}@,
        %{public}@,
        %{public}@
      )
      """, log: log, type: .debug,
           origin as CVarArg,
           downloadTask as CVarArg,
           savedURL as CVarArg
    )

    do {
      try FileManager.default.moveItem(at: location, to: savedURL)
      delegate?.proxy(self, url: origin, successfullyDownloadedTo: savedURL)
    } catch {
      delegate?.proxy(self, url: origin, failedToDownloadWith: error)
      return
    }

  }

}

// MARK: - Managing Files

extension FileProxy {

  private func totalBytes() throws -> Int {
    do {
      let dir = try FileLocator.targetDirectory(identifier: identifier)
      let urls = try FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.fileSizeKey])

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

  private func remove(_ url: URL) throws {
    let fm = FileManager.default

    let attributes = try fm.attributesOfItem(atPath: url.path)

    guard
      let d = attributes[FileAttributeKey.modificationDate] as? Date,
      delegate?.validate(self, removing: url, modified: d) ?? false else {
      os_log("not removing: %{public}@", log: log, url as CVarArg)
      return
    }

    try fm.removeItem(at: url)
  }

  /// Returns URLs of all cached files.
  private func ls() throws -> [URL] {
    let dir = try FileLocator.targetDirectory(identifier: identifier)

    return try FileManager.default.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: [kCFURLIsRegularFileKey as URLResourceKey],
      options: .skipsHiddenFiles
    ).map { $0.standardizedFileURL }
  }

}

// MARK: - FileProxying

extension FileProxy: FileProxying {

  public func activate() {
    sQueue.sync {
      self._sessionsByIds = [SessionIdentifier: Session]()
    }

    isInvalid = false
  }

  public func invalidateSessions() {
    precondition(!isInvalid)

    sQueue.sync {
      let ids: [SessionIdentifier] = _sessionsByIds.compactMap {
        switch $0.value {
        case .background(let id, let s, let cb):
          os_log("invalidating background session: %{public}@", log: log, id)
          s.invalidateAndCancel()
          cb()
          return id
        case .transient(let id, let s):
          os_log("invalidating transient session: %{public}@", log: log, id)
          s.invalidateAndCancel()
          return id
        }
      }

      for id in ids {
        _sessionsByIds.removeValue(forKey: id)
      }
    }
  }

  public func invalidate() {
    precondition(!isInvalid)

    sQueue.sync {
      for s in _sessionsByIds {
        switch s.value {
        case .background(let id, let s, let cb):
          os_log("invalidating background session: %{public}@", log: log, id)
          s.invalidateAndCancel()
          cb()
        case .transient(let id, let s):
          os_log("invalidating transient session: %{public}@", log: log, id)
          s.invalidateAndCancel()
        }
      }

      _sessionsByIds.removeAll()
    }

    _isInvalid = true
  }
  
  public func handleEventsForBackgroundURLSession(
    identifier: String,
    completionBlock: @escaping () -> Void
  ) {
    precondition(!isInvalid)

    if session(matching: identifier) == nil {
      let s = makeSession(identifier: identifier, completionBlock: completionBlock)
      addSession(s, identifier: identifier)
    }
  }

  public func cancelDownloads(matching url: URL) {
    precondition(!isInvalid)

    FileProxy.tasks(in: urlSessions, matching: url) { tasks in
      for task in tasks {
        task.cancel()
      }
    }
  }

  public func removeFile(matching url: URL) -> URL? {
    precondition(!isInvalid)

    guard let localURL = FileLocator(
      identifier: identifier, url: url)?.localURL else {
      return nil
    }

    do {
      try remove(localURL)
    } catch {
      return nil
    }

    return localURL
  }
  
  public func removeAll() throws {
    precondition(!isInvalid)

    for url in try ls() {
      try remove(url)
    }
  }
  
  private static func notOnMain() {
    guard ProcessInfo.processInfo.processName != "xctest" else {
      return
    }
    
    dispatchPrecondition(condition: .notOnQueue(.main))
  }
  
  public func localURL(matching url: URL) throws -> URL? {
    precondition(!isInvalid)
    FileProxy.notOnMain()

    guard let localURL = FileLocator(
      identifier: identifier, url: url)?.localURL else {
      throw FileProxyError.invalidURL(url)
    }

    do {
      if try localURL.checkResourceIsReachable() {
        return localURL.standardizedFileURL
      }
    } catch {
      os_log("no such file", log: log, type: .debug)
    }
    
    return nil
  }

  public func removeAll(keeping urls: [URL]) throws {
    precondition(!isInvalid)

    let preserved = try urls.compactMap { try localURL(matching: $0) }

    for url in Set(try ls()).subtracting(preserved) {
      try remove(url)
    }
  }

  private func hasTasks(matching url: URL, hasBlock: @escaping (Bool) -> Void) {
    FileProxy.tasks(in: urlSessions, matching: url) { tasks in
      hasBlock(!tasks.isEmpty)
    }
  }

  private func makeSessionIdentifier() -> SessionIdentifier {
    return "\(identifier)-\(UUID().uuidString)"
  }
  
  @discardableResult
  public func url(
    matching url: URL,
    start downloading: Bool = true,
    using configuration: DownloadTaskConfiguration? = nil
  ) throws -> URL {
    precondition(!isInvalid)
    FileProxy.notOnMain()

    if let localURL = try localURL(matching: url) {
      return localURL
    }

    guard downloading else {
      return url
    }

    try checkSize()

    selectSession(for: url) { session in
      guard let s = session else {
        return
      }

      let checkedSession: Session = {
        // Got session, but cellular access has been disallowed in the meantime.
        guard self.checkSession(configuration: s.configuration) else {
          self.removeSession(matching: s.configuration.identifier!)

          let newID = self.makeSessionIdentifier()
          let newSession = self.makeSession(identifier: newID)

          self.addSession(newSession, identifier: newID)

          return newSession
        }

        return s
      }()

      let task = checkedSession.downloadTask(with: url)

      if let s = configuration?.countOfBytesClientExpectsToSend {
        task.countOfBytesClientExpectsToSend = s
      }
      if let r = configuration?.countOfBytesClientExpectsToReceive {
        task.countOfBytesClientExpectsToReceive = r
      }
      if let d = configuration?.earliestBeginDate {
        task.earliestBeginDate = d
      }

      os_log("""
        downloading: (
          %{public}@,
          %{public}@
        )
        """, log: log, type: .debug, url as CVarArg, task as CVarArg)

      task.resume()
    }

    return url
  }

  public func url(
    matching url: URL,
    using configuration: DownloadTaskConfiguration? = nil
  ) throws -> URL {
    return try self.url(matching: url, start: true, using: configuration)
  }

  public func url(matching url: URL) throws -> URL {
    return try self.url(matching: url, using: nil)
  }

}
