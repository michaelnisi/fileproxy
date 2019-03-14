//
//  FileProxyDelegate.swift
//  fileproxy
//
//  Created by Michael Nisi on 22.02.18.
//

import Foundation
import os.log

private let log = OSLog.disabled

public protocol FileProxyDelegate: class {

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
    URLSession.AuthChallengeDisposition, URLCredential?) -> Void)

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64)

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    successfullyDownloadedTo location: URL)

  func proxy(
    _ proxy: FileProxying,
    url: URL?,
    didCompleteWithError error: Error?)

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    failedToDownloadWith error: Error)
  
  /// Validates removing of the local file matching remote `url`.
  func validate(
    _ proxy: FileProxying,
    removing url: URL,
    modified: Date
  ) -> Bool
  
  /// Allows to make connections over a cellular network.
  var allowsCellularAccess: Bool { get }
  
  /// Gives the system control over when transfers should occur.
  var isDiscretionary: Bool { get }

}

// MARK: - Default Configuration

public extension FileProxyDelegate {
  var allowsCellularAccess: Bool { return false }
  var isDiscretionary: Bool { return true }
}

// MARK: - Sufficient Defaults for Downloading

public extension FileProxyDelegate {

  public func proxy(
    _ proxy: FileProxying,
    url: URL,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
    URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    os_log("default handling challenge: %{public}@",
           log: log, type: .debug, url as CVarArg, challenge)

    completionHandler(.performDefaultHandling, nil)
  }

  public func proxy(
    _ proxy: FileProxying, url: URL, successfullyDownloadedTo location: URL) {
    os_log("successfullyDownloadedTo: %{public}@",
           log: log, type: .debug, url as CVarArg)
  }

  public func proxy(
    _ proxy: FileProxying, url: URL?, didCompleteWithError error: Error?) {
    os_log("didCompleteWithError: ( %{public}@, %{public}@ )",
           log: log, type: .debug,
           String(describing: url), String(describing: error))
  }

  public func proxy(
    _ proxy: FileProxying, url: URL, failedToDownloadWith error: Error) {
    os_log("failedToDownloadWith: %{public}@",
           log: log, type: .debug, url as CVarArg)
  }

  public func proxy(
    _ proxy: FileProxying,
    url: URL,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64) {
//    os_log("""
//      fileproxy: didWriteData: (
//        %{public}@
//        bytesWritten: %i,
//        totalBytesWritten: %i,
//        totalBytesExpectedToWrite: %i"
//      )
//      """, type: .debug, url as CVarArg,
//           bytesWritten as CVarArg,
//           totalBytesWritten as CVarArg,
//           totalBytesExpectedToWrite as CVarArg
//    )
  }

}

// MARK: - Disallowing Deletions by Default

extension FileProxyDelegate {
  
  func validate(_ proxy: FileProxying, removing url: URL, modified: Date) -> Bool {
    return false
  }
  
}
