import XCTest
@testable import fileproxy

class fileproxyTests: XCTestCase {

  func testInit() {
    XCTAssertNotNil(Foxy().session)
  }

  func testLocate() {
    let proxy = Foxy()
    let url = URL(string: "http://abc.de/resources/file")!
    let loc = proxy.locate(url: url)
    dump(loc)
    XCTAssertEqual(loc.remoteURL, url)
  }

  static var allTests = [
    ("testInit", testInit),
    ("testLocate", testLocate),
  ]
}
