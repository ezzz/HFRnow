import Foundation
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004): every topic oracle of LOT-003 against `MessageBlockParser` on its capture.
/// Only the message-level fields in the LOT-030 scope are compared; action links, quotes, `toHTML` and the
/// actions dictionary belong to LOT-031/032/034 (`docs/lots/LOT-030-message-blocks.md`, "Oracle coverage").
@Suite("Message blocks vs LOT-003 oracle")
struct MessageBlockOracleTests {
    /// Every case of `Fixtures/LOT-003/oracle-map.json`; `coversEveryOracle` fails when the map gains one.
    static let cases = [
        "P03m", "R20", "R21", "R22a", "R22b", "R23", "R24", "R26", "R27", "R27b", "R28", "R31", "R32a", "R32b",
        "RA1", "RA2", "RA3", "RA4", "RA5", "RU1", "RU2", "R96c", "R96d"
    ]

    /// `cases` and the M2 topic captures; the other oracle suites keep reading `cases` (the LOT-003 map alone).
    static let allCases = cases + m2Folders.keys.sorted()

    /// The M2 topic captures (#475) and the `Fixtures` folder of their oracle: R122a locked topic, logged in; R122c and R122d
    /// topic pages reached from a search (filter checked, filter off); R130a MP thread whose first message starts with a newline.
    static let m2Folders = ["R122a": "M2-readonly", "R122c": "M2-readonly", "R122d": "M2-readonly", "R130a": "M2-misc"]

    /// Filtered search pages (`filter=1`): legacy's `dicoHTML` starts with the link back to the unfiltered topic (difference 8).
    static let filteredSearchCases: Set = ["R122c"]

    @Test("The case list matches the oracle map")
    func coversEveryOracle() throws {
        var mapped = Set<String>()
        for folder in [nil, "M2-readonly", "M2-misc"] {
            let map = try TopicOracle.loadMap(folder: folder)
            mapped.formUnion(map.filter { $0.value.kind == "topic" }.keys)
        }
        #expect(mapped == Set(Self.allCases))
    }

    @Test("Message-level fields equal the legacy LinkItem", arguments: allCases)
    func matchesOracle(caseID: String) throws {
        let folder = Self.m2Folders[caseID]
        let map = try TopicOracle.loadMap(folder: folder)
        let entry = try #require(map[caseID])
        let oracle = try TopicOracle.load(caseID, folder: folder)
        #expect(oracle.exception == nil)
        let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: entry))
        try #require(blocks.count == oracle.result.messages.count, "\(caseID): block count")

        var avatarRequests = oracle.sideEffects.networkRequests[...]
        for (block, expected) in zip(blocks, oracle.result.messages) {
            let label = "\(caseID) message \(expected.index)"
            #expect("t\(block.numreponse)" == expected.postID, "\(label): postID")
            #expect(block.author == expected.name, "\(label): name")
            #expect(block.isDeleted == expected.isDel, "\(label): isDel")
            #expect(block.dateText == expected.messageDate, "\(label): messageDate")
            // Legacy keeps the U+00A0 of the trailer (LOT-003 Q28); the parser's text is whitespace-normalized.
            let editedTime = expected.editedTime?.replacing("\u{00A0}", with: " ")
            #expect(block.editNote == editedTime, "\(label): editedTime")
            #expect(block.quotedByCount == expected.quotedNB.flatMap { Int($0) }, "\(label): quotedNB")
            #expect(block.quotedByURL == expected.quotedLINK.flatMap { HFRURL.absolute($0) }, "\(label): quotedLINK")

            // The legacy avatar is a cache path set once the download of the block's own `avatar_center` image completed
            // (LOT-003 Q33, RC3.2): the URL it fetched is the next recorded request.
            if expected.imageUI != nil {
                #expect(block.avatarURL?.absoluteString == avatarRequests.popFirst(), "\(label): avatar URL")
            } else {
                #expect(block.avatarURL == nil, "\(label): no avatar")
            }

            // Legacy has no continuation flag; the quote link of that block carries `ref=0` (HFR-PROTOCOL §4).
            let isFirstOfPreviousPage = expected.urlQuoteDecoded?.contains("&ref=0&") ?? false
            #expect(block.isContinuation == isFirstOfPreviousPage, "\(label): continuation")

            var oracleHTML = try #require(expected.dicoHTML, "\(label): dicoHTML")
            if Self.filteredSearchCases.contains(caseID) {
                // Difference 8 (LOT-030): on a filtered search page legacy prepends the "Voir ce message dans le sujet non
                // filtré" link, the second child of `messCase2` (`ParseMessagesOperation.m:364-368` @ 2440d79). The port's
                // content is the `para` element only: check the prefix is exactly that link, then compare the rest.
                let link = "Voir ce message dans le sujet non filtré</b></a>"
                let hasLink = oracleHTML.hasPrefix("<a href=\"/forum2.php?") && oracleHTML.contains(link + "<div id=\"para")
                #expect(hasLink, "\(label): legacy search link")
                let start = try #require(oracleHTML.firstRange(of: "<div id=\"para"))
                oracleHTML = String(oracleHTML[start.lowerBound...])
            } else {
                #expect(!oracleHTML.hasPrefix("<a "), "\(label): no search link outside a filtered page")
            }
            let expectedShape = try HTMLShape(insideOf: oracleHTML)
            let actualShape = try HTMLShape(fragment: block.contentHTML)
            #expect(actualShape == expectedShape, "\(label): content shape, \(actualShape.firstDifference(from: expectedShape))")
        }
        #expect(avatarRequests.isEmpty, "\(caseID): every avatar request is matched by a block")
    }

    @Test("The shape comparison is not vacuous")
    func shapeDetectsDifferences() throws {
        let reference = try HTMLShape(insideOf: "<div id=\"para1\"><p>a <b>b</b><br>c</p></div>")
        #expect(try HTMLShape(fragment: "<p>a <b>b</b><br />c</p>") == reference)
        #expect(try HTMLShape(fragment: "<p>a <b>b</b><br />c</p><p></p>") == reference, "empty paragraphs are not part of the shape")
        #expect(try HTMLShape(fragment: "<p>a <span>b</span><br />c</p>") != reference)
        #expect(try HTMLShape(fragment: "<p>a <a href=\"x\">b</a><br />c</p>") != reference)
        #expect(try HTMLShape(fragment: "<p>a <b>b</b><br />d</p>") != reference)
        #expect(try HTMLShape(fragment: "<p>a <b>b</b><br />c<img src=\"x\"></p>") != reference)
    }
}
