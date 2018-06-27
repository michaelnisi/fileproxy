//
//  FileProxyDelegate.swift
//  fileproxy
//
//  Created by Michael Nisi on 22.02.18.
//

import Foundation
import os.log

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
  
  func validate(
    _ proxy: FileProxying,
    removing url: URL,
    modified: Date
  ) -> Bool

}

/// MARK: - Downloading

extension FileProxyDelegate {

  public func proxy(
    _ proxy: FileProxying,
    url: URL,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
    URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    if #available(iOS 11.0, macOS 10.12, *) {
      os_log("fileproxy: default handling challenge: %{public}@",
             type: .debug, url as CVarArg, challenge)
    }

    completionHandler(.performDefaultHandling, nil)
  }

  public func proxy(
    _ proxy: FileProxying, url: URL, successfullyDownloadedTo location: URL) {
    if #available(iOS 11.0, macOS 10.12, *) {
      os_log("fileproxy: successfullyDownloadedTo: %{public}@",
             type: .debug, url as CVarArg)
    }
  }

  public func proxy(
    _ proxy: FileProxying, url: URL?, didCompleteWithError error: Error?) {
    if #available(iOS 11.0, macOS 10.12, *) {
      os_log("fileproxy: didCompleteWithError: %{public}@",
             type: .debug, String(describing: url))
    }
  }

  public func proxy(
    _ proxy: FileProxying, url: URL, failedToDownloadWith error: Error) {
    if #available(iOS 11.0, macOS 10.12, *) {
      os_log("fileproxy: failedToDownloadWith: %{public}@",
             type: .debug, url as CVarArg)
    }
  }

  public func proxy(
    _ proxy: FileProxying,
    url: URL,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64) {
//    os_log("""
//      fileproxy: didWriteData: {
//        %{public}@
//        bytesWritten: %i,
//        totalBytesWritten: %i,
//        totalBytesExpectedToWrite: %i"
//      }
//      """, type: .debug, url as CVarArg,
//           bytesWritten as CVarArg,
//           totalBytesWritten as CVarArg,
//           totalBytesExpectedToWrite as CVarArg
//    )
  }

}

// MARK: - Removing Files

extension FileProxyDelegate {
  
  func validate(_ proxy: FileProxying, removing url: URL, modified: Date) -> Bool {
    return false
  }
  
}
