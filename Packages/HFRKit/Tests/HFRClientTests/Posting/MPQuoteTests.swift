import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-058, MP quote: a conversation's quote links (LOT-031, `RA1`-`RA4`) load through LOT-048's `loadForm` as they are,
/// and `R47a`'s prefill is the one legacy read (LOT-004 oracle). No new code: the MP quote is the topic quote path.
@Suite("MP quote")
struct MPQuoteTests {
    /// The quote links of the conversation page `file`, as LOT-031 reads them.
    private static func quoteLinks(_ file: String) throws -> [URL] {
        try MessageActionsParser.actions(in: try Capture.page(file)).compactMap(\.quoteURL)
    }

    @Test("Every quote link of the captured conversations is accepted by the form loader", arguments: [
        "RA1-mp-thread-after-create", "RA2-mp-thread-crlf-lf-nonbmp", "RA3-mp-thread-before-cleanup", "RA4-mp-thread-both-accounts"
    ])
    func linksAccepted(file: String) throws {
        let links = try Self.quoteLinks(file)
        #expect(!links.isEmpty)
        #expect(links.allSatisfy { PostingFlow.isForumPage($0) && $0.path() == "/message.php" })
        #expect(links.allSatisfy { HFRURL.queryValue(named: "cat", in: $0.absoluteString) == "prive" })
    }

    @Test("RA4's link to message 1980875030 is R47a's request; its prefill equals the LOT-004 oracle, as served")
    func prefill() async throws {
        let target = try PostingCapture.pageURL("R47a")
        let link = try #require(try Self.quoteLinks("RA4-mp-thread-both-accounts").first {
            HFRURL.queryValue(named: "numrep", in: $0.absoluteString) == "1980875030"
        })
        var withoutFragment = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false))
        withoutFragment.fragment = nil
        #expect(withoutFragment.url == target)
        let session = ScriptedPostingSession([try PostingCapture.form("R47a")])
        let form = try await PostingFlow().loadForm(at: link, through: session)
        #expect(form.shape == .reply)
        let oracle = try Lot004Prefill.contentForm("R47a")
        #expect(form.form.textareaContent == oracle)
        #expect(await session.requests.map(\.url) == [link])
    }

    @Test("A link that is not a forum page is refused before any request")
    func refused() async throws {
        let session = ScriptedPostingSession([])
        let link = try #require(URL(string: "https://example.org/message.php?config=hfr.inc&cat=prive&post=3207033&numrep=1"))
        await #expect(throws: PostingError.invalidFormURL) { try await PostingFlow().loadForm(at: link, through: session) }
        #expect(await session.requests.isEmpty)
    }
}

/// `result.legacy.contentForm` of a LOT-004 form oracle (line breaks `\n`, entities decoded).
enum Lot004Prefill {
    static func contentForm(_ id: String) throws -> String {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-004/\(id).oracle.json")
        let root = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        let legacy = (root?["result"] as? [String: Any])?["legacy"] as? [String: Any]
        guard let value = legacy?["contentForm"] as? String else { throw Capture.Missing(name: id + ".oracle contentForm") }
        return value
    }
}
