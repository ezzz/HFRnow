import Foundation
import Testing
@testable import HFRParsing

@Test func moduleIsLinked() {
    #expect(HFRParsing.moduleName == "HFRParsing")
}

@Test func parsesDocumentTitle() throws {
    let html = "<html><head><title>  Hardware.fr  </title></head><body></body></html>"
    #expect(try HFRParsing.documentTitle(in: html) == "Hardware.fr")
}

@Test func returnsNilWhenTitleMissing() throws {
    #expect(try HFRParsing.documentTitle(in: "<html><body></body></html>") == nil)
}

@Test func fixturesBundleIsAvailable() {
    #expect(Bundle.module.url(forResource: "Fixtures", withExtension: nil) != nil)
}
