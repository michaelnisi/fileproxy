import XCTest
@testable import fileproxy

class fileproxyTests: XCTestCase {

  class TestDelegate: FileProxyDelegate {

    private let expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
      self.expectation = expectation
    }

    var error: Error?

    func proxy(
      _ proxy: FileProxying,
      url: URL?, didCompleteWithError error: Error?
    ) {
      self.error = error
      expectation.fulfill()
    }

    func proxy(
      _ proxy: FileProxying,
      url: URL,
      successfullyDownloadedTo location: URL) {
      expectation.fulfill()
    }

    func proxy(
      _ proxy: FileProxying,
      url: URL,
      failedToDownloadWith error: Error) {
      self.error = error
      expectation.fulfill()
    }

  }

//  func testForUnresolvableURL() {
//    let exp = self.expectation(description: "url")
//    exp.assertForOverFulfill = false
//
//    let delegate = TestDelegate(expectation: exp)
//    let proxy = FileProxy(delegate: delegate)
//
//    let url = URL(string: "http://abc.de/resources/file")!
//    let found = try! proxy.url(for: url)
//
//    self.waitForExpectations(timeout: 10) { er in
//      XCTAssertNil(er)
//      XCTAssertEqual(found, url)
//    }
//  }

  func testForRresolvableURL() {
    let exp = self.expectation(description: "url")
    exp.assertForOverFulfill = false

    let delegate = TestDelegate(expectation: exp)
    let proxy = FileProxy(delegate: delegate)

    let url = URL(string: "http://localhost:8000/urandom")!
    let found = try! proxy.url(for: url)

    guard !found.isFileURL else {
      fatalError("unexpected state: remove donwloads before testing")
    }

    self.waitForExpectations(timeout: 5) { er in
      XCTAssertNil(er)
      XCTAssertEqual(found, url)
      guard delegate.error == nil else {
        fatalError()
      }
      let localURL = try! proxy.url(for: url)
      XCTAssert(localURL.isFileURL)
    }
  }

}
