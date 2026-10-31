import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-038: the MPStorage thread on the MP list and its document, against the LOT-004 storage oracles and the raw captures.
@Suite("MPStorage page parser")
struct MPStoragePageParserTests {
    /// The URL legacy's `find` requested for page 1 (`MPStorage.m:694`), as every `S-find-*` oracle records it.
    static let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1&subcat=&sondage=0&owntopic=0"
        + "&trash=0&trash_post=0&moderation=0&new=0&nojs=0&subcatgroup=0"

    @Test("find reproduces the legacy oracle: the post id on page 1, nothing on R13a",
          arguments: ["S-find-R13u1", "S-find-R13u1b", "S-find-R13a"])
    func findMatchesOracle(_ caseID: String) throws {
        let oracle = try StorageOracle.load(caseID)
        #expect(oracle.requestedURLs == [Self.listURL])
        let html = try Fixture.capture(try #require(oracle.responses.first))
        let search = try MPStoragePageParser.findThread(in: html, pageURL: Self.listURL)
        if let post = oracle.postID {
            #expect(oracle.returned)
            #expect(search == .found(post: try #require(Int(post))))
        } else {
            #expect(!oracle.returned)
            // Legacy issued one GET: its pager read one page, so there is no next page to walk to.
            guard case .notOnPage(let navigation) = search else {
                Issue.record("expected notOnPage, got \(search)")
                return
            }
            #expect(navigation.nextPath == nil)
            #expect(navigation.last == 1)
        }
    }

    @Test("The storage row of R13u1 carries HFR's [non lu] marker and is still found")
    func findsMarkedRow() throws {
        let html = try Fixture.capture("R13u1-mp-list-recipient-unread")
        #expect(html.contains("<span class=\"red\" title=\"Ce message n'a pas été lu par : user117\">[non lu]</span> <a href="))
        #expect(try MPStoragePageParser.findThread(in: html, pageURL: Self.listURL) == .found(post: 3_157_083))
    }

    @Test("Only the subject itself, with or without the [non lu] prefix, is the storage thread")
    func subjectMatchIsExact() {
        let subject = MPStorageDocument.subject
        #expect(MPStoragePageParser.isStorageSubject(subject))
        #expect(MPStoragePageParser.isStorageSubject("[non lu] \(subject)"))
        for title in ["Re: \(subject)", "\(subject) bis", "x\(subject)", subject.uppercased(), "[non lu]\(subject)", "", "[non lu] "] {
            #expect(!MPStoragePageParser.isStorageSubject(title), "\(title)")
        }
    }

    @Test("R60a: numreponse and document equal the oracle's sNumRep and dData")
    func readMatchesOracle() throws {
        let oracle = try StorageOracle.load("R60a")
        let html = try Fixture.capture("R60a-mpstorage-thread-first-post")
        guard case .storage(let message) = try MPStoragePageParser.readDocument(in: html) else {
            Issue.record("R60a is the storage thread")
            return
        }
        #expect(message.numreponse == Int(try #require(oracle.numreponse)))
        let expected = try MPStorageCodec.decode(try #require(oracle.documentJSON))
        #expect(message.document == expected)
        #expect(message.document.data.count == 1)
    }

    @Test("R60a: the text handed to the codec is the stored JSON byte for byte, its numbers as written")
    func readKeepsTextExact() throws {
        let html = try Fixture.capture("R60a-mpstorage-thread-first-post")
        // Independent of the parser: the raw paragraph of `div#para<numreponse>`, entities decoded by hand (only `&#034;` occurs).
        let raw = try #require(html.firstMatch(of: #/<div id="para1980164061"><p>(.*?)<div style="clear: both;">/#)).output.1
        #expect(!raw.contains("&") || raw.contains("&#034;"))
        let stored = String(raw).replacing("&#034;", with: "\"")
        guard case .storage(let message) = try MPStoragePageParser.readDocument(in: html) else {
            Issue.record("R60a is the storage thread")
            return
        }
        #expect(message.text == stored)
        #expect(message.text.contains("\"lastUpdate\":1745779603553"))
    }

    @Test("RA5, HFR's \"pas destiné\" page, is the notAddressed result")
    func notAddressed() throws {
        let html = try Fixture.capture("RA5-mp-thread-after-delete-owner")
        #expect(html.contains("Ce message ne vous est pas destiné"))
        #expect(try MPStoragePageParser.readDocument(in: html) == .notAddressed)
    }

    @Test("Pages that are not the storage thread's first page throw, never give a document", arguments: [
        ("RA1-mp-thread-after-create", MPStoragePageError.notStorageThread),
        ("RU1-mp-thread-recipient-view", MPStoragePageError.notStorageThread),
        ("R20-topic-p1-anon", MPStoragePageError.notStorageThread),
        ("R22a-topic-middle-page-anon", MPStoragePageError.notFirstPage),
        ("R13a-mp-list", MPStoragePageError.noMessage),
        // A `.hop` notice that is not the "destiné" one ("Aucun sujet que vous avez lu n'est connu").
        ("R12-favourites-anon", MPStoragePageError.noMessage)
    ])
    func otherPagesThrow(_ name: String, _ expected: MPStoragePageError) throws {
        let html = try Fixture.capture(name)
        #expect(throws: expected) { try MPStoragePageParser.readDocument(in: html) }
    }
}

/// A LOT-004 `storage` oracle (`Fixtures/LOT-004/<case>.oracle.json`): the legacy `find` or page parse on one capture.
private struct StorageOracle {
    /// `returned` of `find`, or of the page parse.
    let returned: Bool
    let requestedURLs: [String]
    let postID: String?
    let numreponse: String?
    /// `state.dData` re-serialized: the legacy dictionary, so key order and number spelling are not the page's.
    let documentJSON: String?
    /// Capture names of the spec file's `responses` (`find` cases only).
    let responses: [String]

    static func load(_ caseID: String) throws -> StorageOracle {
        let directory = "Fixtures/LOT-004"
        let root = try object(Fixture.text("\(caseID).oracle", extension: "json", subdirectory: directory))
        #expect(root["kind"] as? String == "storage")
        let result = try #require(root["result"] as? [String: Any])
        let state = try #require(result["state"] as? [String: Any])
        let requests = (result["requests"] as? [[String: Any]]) ?? []
        var responses: [String] = []
        if result["op"] as? String == "find" {
            let spec = try object(Fixture.text(caseID, extension: "json", subdirectory: directory))
            responses = ((spec["responses"] as? [String]) ?? []).map {
                String($0.split(separator: "/").last ?? "").replacing(".html", with: "")
            }
        }
        let document = try state["dData"].flatMap { $0 is NSNull ? nil : $0 }.map {
            try #require(String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8))
        }
        return StorageOracle(
            returned: try #require((result["returned"] ?? (result["parse"] as? [String: Any])?["returned"]) as? Bool),
            requestedURLs: requests.compactMap { $0["url"] as? String },
            postID: state["sPostId"] as? String,
            numreponse: state["sNumRep"] as? String,
            documentJSON: document,
            responses: responses
        )
    }

    private static func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
