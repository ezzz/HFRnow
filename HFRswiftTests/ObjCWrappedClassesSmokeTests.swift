import XCTest
@testable import HFRswift

final class ObjCWrappedClassesSmokeTests: XCTestCase {
    func testWrappedObjCClassesCanBeInstantiated() {
        XCTAssertNotNil(FavoritesTableViewController())
        XCTAssertNotNil(HFRMPViewController())
        XCTAssertNotNil(MessagesTableViewController())
    }

    func testObjCWrappedClassesCoverageIsTrackedInPlan() throws {
        throw XCTSkip("Detailed wrapped ObjC behavior tests will be added once the test target is wired in CI and simulator platform setup is stable.")
    }
}
