//
//  FileProxying.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation

public typealias HTTPStatusCode = Int

/// Enumerates specific errors for this package.
public enum FileProxyError: Error {
  case fileSizeRequired
  case http(HTTPStatusCode)
  case invalidURL(URL)
  case maxBytesExceeded(Int)
  case targetRequired
}

/// The system appreciates it if you configure your download tasks.
public struct DownloadTaskConfiguration {
  let countOfBytesClientExpectsToSend: Int64?
  let countOfBytesClientExpectsToReceive: Int64?
  let earliestBeginDate: Date?
}

/// Blurs the line between local and remote files with long-running nonurgent
/// transfers.
public protocol FileProxying {

  /// Identifies this proxy.
  var identifier: String { get }

  /// The maximum size of the target directory in bytes. If the target
  /// directory's size exceeds this maximum, downloaded files are removed,
  /// oldest first.
  var maxBytes: Int { get }

  /// A callback delegate.
  var delegate: FileProxyDelegate? { get set }

  /// Handles events for background URL session matching `identifier`.
  func handleEventsForBackgroundURLSession(
    identifier: String,
    completionHandler: @escaping () -> Void
  )

  /// Returns a local file URL matching remote `url` if a file has been
  /// downloaded or `nil` if not.
  func localURL(matching url: URL) throws -> URL?

  /// Returns proxied URL matching `url` and if the file doesn’t exist locally,
  /// asks the system to download the file in the background. The proxied URL
  /// is either the local file URL or the original remote URL.
  ///
  /// - Parameters:
  ///   - url: The remote URL to proxy.
  ///   - downloading: Set to `false` to prevent automatic downloading.
  ///   - configuration: An optional download task configuration.
  ///
  /// - Throws: Invalid URLs or file IO errors could produce errors.
  ///
  /// - Returns: A local file URL or the original remote URL.
  @discardableResult func url(
    matching url: URL,
    start downloading: Bool,
    using configuration: DownloadTaskConfiguration?
  ) throws -> URL
  
  @discardableResult func url(
    matching url: URL,
    using configuration: DownloadTaskConfiguration?
  ) throws -> URL
  
  @discardableResult func url(matching url: URL) throws -> URL

  /// Removes local file matching `url`.
  func removeFile(matching url: URL) -> URL?

  /// Removes all locals files that have been downloaded.
  func removeAll() throws

  /// Removes all local files except the files matching `urls`.
  func removeAll(keeping urls: [URL]) throws

  /// Cancels download tasks matching `url`.
  func cancelDownloads(matching url: URL)

  /// Invalidates this file proxy.
  ///
  /// - Parameters:
  ///   - finishing: Pass `true` to finish current download tasks.
  func invalidate(finishing: Bool)

}


