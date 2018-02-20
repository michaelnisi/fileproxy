import Foundation

public typealias URLHash = String
public typealias RemoteURL = URL

/// Locates or identifies a file.
public struct FileLocator {
  let localURL: URL?
  let remoteURLHash: URLHash
  let remoteURL: RemoteURL
}

/// Blurs the line between local and remote files with longrunning nonurgent
/// transfers.
public protocol FileProxy: URLSessionDelegate {

  /// The background session to use.
  var session: URLSession { get }

  // TODO: var target: URL { get }

  /// Locates the file at `url` and returns its file locator. If the file is
  /// is not locally available, in the documents directory, a background
  /// download is started. If the background download finishes while the
  /// program is still running, the completion block is submitted to a
  /// global dispatch queue.
  ///
  /// - Parameters:
  ///   - url: The remote URL of a file.
  ///   - downloadComplete: The block to run once the download finished.
  ///
  /// - Returns: Returns the file locator, containing the local file URL if available.
  func locate(url: RemoteURL,
    downloadComplete: ((_ locator: FileLocator, _ error: Error?) -> Void)?
  ) -> FileLocator
}

/// MARK: - Hashing

extension FileProxy {

  private static func djb2Hash(string: String) -> Int {
    let unicodeScalars = string.unicodeScalars.map { $0.value }
    return Int(unicodeScalars.reduce(5381) {
      ($0 << 5) &+ $0 &+ Int($1)
    })
  }

  /// Returns unsafe hash of `url`.
  static func hash(url: RemoteURL) -> String {
    let str = url.absoluteString
    let hash = djb2Hash(string: str)
    return String(hash)
  }

}

extension FileProxy {

  func locate(url: RemoteURL,
    downloadComplete: ((_ locator: FileLocator, _ error: Error?) -> Void)? = nil
  ) -> FileLocator {
    let uid = Self.hash(url: url)

    if #available(macOS 10.12, *) {
      let fm = FileManager.default
      let documents = fm.temporaryDirectory // obviously not
      let localURL = URL(string: uid, relativeTo: documents)
      dump(localURL)
    }

    let loc = FileLocator(localURL: nil, remoteURLHash: uid, remoteURL: url)
    return loc
  }

}

final class Foxy: NSObject, FileProxy {

  lazy var session: URLSession = {
    let id = "ink.codes.foxy"
    let conf = URLSessionConfiguration.background(withIdentifier: id)
    conf.isDiscretionary = true

    #if os(iOS)
      conf.sessionSendsLaunchEvents = true
    #endif

    return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
  }()

}

