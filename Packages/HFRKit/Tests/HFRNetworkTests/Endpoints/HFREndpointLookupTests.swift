import Testing
@testable import HFRNetwork

struct HFREndpointLookupTests {
    private static let smiley = "https://forum.hardware.fr/message-smi-mp-aj.php?config=hfr.inc&findsmilies="

    @Test(arguments: [
        ("chat", false, "chat"),
        ("  chat noir ", false, "chat%20noir"),
        ("chat\nnoir\tgris", false, "chat%20noir%20gris"),
        ("chat noir", true, "%2Bchat%20%2Bnoir"),
        ("++chat +noir", true, "%2Bchat%20%2Bnoir"),
        ("++chat +noir", false, "chat%20noir"),
        ("éclair", false, "%C3%A9clair"),
        ("a&b=c", false, "a%26b%3Dc")
    ])
    func smileySearch(text: String, requireAll: Bool, encoded: String) throws {
        let request = try HFREndpoint.smileySearch(text, requireAll: requireAll)
        #expect(request.url.absoluteString == Self.smiley + encoded)
        #expect(request.method == .get)
    }

    @Test(arguments: ["", "  ", "ab", " ab ", "a\n\t"])
    func smileySearchRefusesShortText(text: String) {
        #expect(throws: NetworkError.self) { try HFREndpoint.smileySearch(text) }
    }

    @Test(arguments: [
        ("forums/hardwarefr/categories/", nil as Int?, nil as Int?,
         "uri=forums/hardwarefr/categories/"),
        ("forums/hardwarefr/categories/13/topics/last/", 2, nil,
         "uri=forums/hardwarefr/categories/13/topics/last/&page=2"),
        ("forums/hardwarefr/categories/13/topics/last/", 2, 50,
         "uri=forums/hardwarefr/categories/13/topics/last/&page=2&results_per_page=50"),
        ("a b?c&d", nil, 25, "uri=a%20b%3Fc%26d&results_per_page=25")
    ])
    func rest(uri: String, page: Int?, perPage: Int?, query: String) throws {
        let request = try HFREndpoint.rest(uri: uri, page: page, resultsPerPage: perPage)
        #expect(request.url.absoluteString == "https://forum.hardware.fr/webservices/rest_api.php?" + query)
    }

    @Test func restRefusesBadInput() {
        #expect(throws: NetworkError.self) { try HFREndpoint.rest(uri: "") }
        #expect(throws: NetworkError.self) { try HFREndpoint.rest(uri: "x", page: 0) }
        #expect(throws: NetworkError.self) { try HFREndpoint.rest(uri: "x", resultsPerPage: 0) }
    }
}
