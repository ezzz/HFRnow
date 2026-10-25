import Foundation
import Testing
@testable import HFRModels

@Suite struct CategoryIDTests {
    @Test(arguments: [
        ("13", CategoryID.forum(13)),
        ("0", CategoryID.forum(0)),
        ("prive", CategoryID.privateMessages)
    ])
    func parsesQueryValues(value: String, expected: CategoryID) {
        #expect(CategoryID(queryValue: value) == expected)
    }

    @Test(arguments: ["", "-1", "+5", "1.5", " 13", "13 ", "Prive", "abc", "99999999999999999999", "١٢"])
    func rejectsInvalidQueryValues(value: String) {
        #expect(CategoryID(queryValue: value) == nil)
    }

    @Test func queryValueIsTheInverseOfParsing() {
        #expect(CategoryID.forum(13).queryValue == "13")
        #expect(CategoryID.privateMessages.queryValue == "prive")
    }

    @Test func codableUsesTheQueryString() throws {
        let data = try JSONEncoder().encode([CategoryID.forum(13), .privateMessages])
        #expect(try text(of: data) == #"["13","prive"]"#)
        #expect(try JSONDecoder().decode([CategoryID].self, from: data) == [.forum(13), .privateMessages])
    }

    @Test func decodingRejectsUnknownStrings() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CategoryID].self, from: Data(#"["nope"]"#.utf8))
        }
    }
}
