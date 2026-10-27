import HFRParsing
@testable import SwiftHFR
import Testing

struct EngineInfoTests {
    @Test func linksEveryHFRKitModule() {
        #expect(EngineInfo.linkedModules == ["HFRModels", "HFRParsing", "HFRNetwork", "HFRStorage", "HFRClient"])
    }

    @Test func engineRunsInsideTheAppHost() throws {
        // Calls real engine code (SwiftSoup through HFRParsing) from the app's test bundle.
        let title = try HFRParsing.documentTitle(in: "<html><head><title> Hardware.fr </title></head></html>")
        #expect(title == "Hardware.fr")
    }
}
