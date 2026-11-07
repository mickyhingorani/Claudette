import XCTest
@testable import Claudette

final class SmokeTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
