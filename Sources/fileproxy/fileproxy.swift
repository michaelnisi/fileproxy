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

extension FileProxy {

  func locate(url: RemoteURL,
    downloadComplete: ((_ locator: FileLocator, _ error: Error?) -> Void)? = nil
  ) -> FileLocator {
    let uid = UUID().uuidString
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

