import XCTest
@testable import HFRswift

final class ObjCWrappedClassesSmokeTests: XCTestCase {
    func testWrappedObjCClassesRemainAvailableAtRuntime() {
        for className in [
            "FavoritesTableViewController",
            "HFRMPViewController",
            "MessagesTableViewController"
        ] {
            let objectClass = NSClassFromString(className) as? NSObject.Type
            XCTAssertNotNil(objectClass, "Missing runtime class \(className)")
            XCTAssertNotNil(objectClass?.init(), "Unable to instantiate \(className)")
        }
    }

    func testObjCWrappedClassesCoverageIsTrackedInPlan() throws {
        throw XCTSkip("Detailed wrapped ObjC behavior tests will be added once the test target is wired in CI and simulator platform setup is stable.")
    }
}
