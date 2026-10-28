import Foundation
import HFRModels
import Testing
@testable import HFRParsing

@Suite("Message quote analyzer")
struct MessageQuoteAnalyzerTests {
    /// A header in HFR's shape (`R20`, `R26`), around `inner`.
    private static func citation(
        _ author: String,
        link: String = "/hfr/Discussions/Loisirs/topic-sujet_1_1.htm#t42",
        tag: String = "citation",
        inner: String = "<p>x</p>"
    ) -> String {
        """
        <div class="container"><table class="\(tag)"><tr class="none"><td>\
        <b class="s1"><a href="\(link)" class="Topic">\(author)</a></b><br><br>\(inner)</td></tr></table></div>
        """
    }

    private static func quotes(_ html: String) throws -> [MessageQuote] {
        try MessageQuoteAnalyzer.quotes(inContentHTML: html)
    }

    @Test("A message without quote has none")
    func noQuote() throws {
        #expect(try Self.quotes("<p>hello</p>").isEmpty)
        #expect(try Self.quotes("").isEmpty)
    }

    @Test("Author and cited number of a plain quote")
    func plain() throws {
        #expect(try Self.quotes(Self.citation("user4 a écrit :")) == [MessageQuote(author: "user4", depth: 1, citedNumreponse: 42)])
    }

    @Test("An outer quote comes before the quotes it contains, depth counts the quote ancestors")
    func nesting() throws {
        let inner = Self.citation("bob a écrit :", link: "/x.htm#t7", inner: Self.citation("carol a écrit :", link: "/x.htm#t3"))
        let html = Self.citation("alice a écrit :", link: "/x.htm#t9", inner: inner) + "<p>reply</p>" + Self.citation("dave a écrit :")
        #expect(try Self.quotes(html) == [
            MessageQuote(author: "alice", depth: 1, citedNumreponse: 9),
            MessageQuote(author: "bob", depth: 2, citedNumreponse: 7),
            MessageQuote(author: "carol", depth: 3, citedNumreponse: 3),
            MessageQuote(author: "dave", depth: 1, citedNumreponse: 42)
        ])
    }

    @Test("A nested quote does not lend its header to an outer quote that has none")
    func headerBelongsToItsOwnTable() throws {
        let outer = #"<table class="citation"><tr><td>\#(Self.citation("bob a écrit :", link: "/x.htm#t7"))</td></tr></table>"#
        #expect(try Self.quotes(outer) == [
            MessageQuote(author: nil, depth: 1, citedNumreponse: nil),
            MessageQuote(author: "bob", depth: 2, citedNumreponse: 7)
        ])
    }

    @Test("An anonymous quote (`table.quote`) has no author and no cited number")
    func anonymous() throws {
        let html = #"<table class="quote"><tr class="none"><td><b class="s1">Citation :</b><br><br><p>x</p></td></tr></table>"#
        #expect(try Self.quotes(html) == [MessageQuote(author: nil, depth: 1, citedNumreponse: nil)])
    }

    @Test("`oldcitation` is a quote like `citation` (legacy renamed it, ParseMessagesOperation.m:191-194)")
    func oldCitation() throws {
        let html = Self.citation("user3 a écrit :", link: "/forum2.php?cat=25&post=8900&numreponse=0#t933309", tag: "oldcitation")
        #expect(try Self.quotes(html) == [MessageQuote(author: "user3", depth: 1, citedNumreponse: 933_309)])
    }

    @Test("Spoilers and code blocks are not quotes, and do not count in the depth")
    func otherTables() throws {
        let spoiler = #"<table class="spoiler"><tr><td><b class="s1Topic">Spoiler :</b><div class="Topic masque">x</div></td></tr></table>"#
        let html = spoiler + Self.citation("bob a écrit :", inner: spoiler) + #"<table class="code"><tr><td>x</td></tr></table>"#
        #expect(try Self.quotes(html) == [MessageQuote(author: "bob", depth: 1, citedNumreponse: 42)])
    }

    @Test("Header text: non-breaking space and zero-width space are normalized, a pseudo may contain spaces and `a écrit`")
    func authorText() throws {
        #expect(try Self.quotes(Self.citation("us\u{200B}er\u{00A0}one a\u{00A0}écrit\u{00A0}:")).first?.author == "user one")
        #expect(try Self.quotes(Self.citation("Mr a écrit a écrit :")).first?.author == "Mr a écrit")
    }

    @Test("A header that is not `<author> a écrit :` gives no author, and an empty author neither")
    func headerWithoutSuffix() throws {
        #expect(try Self.quotes(Self.citation("Citation de bob")).first?.author == nil)
        #expect(try Self.quotes(Self.citation("a écrit :")).first?.author == nil)
        #expect(try Self.quotes(Self.citation("Citation de bob")).first?.citedNumreponse == 42)
    }

    @Test("The cited number is the whole `t<digits>` fragment, nothing else", arguments: [
        "/x.htm", "/x.htm#", "/x.htm#bas", "/x.htm#t", "/x.htm#t12x", "/x.htm#xt12", "/x.htm#t-1", "/x.htm#t99999999999999999999",
        "/x.htm?a=#t1&b=2"
    ])
    func citedNumberRejected(link: String) throws {
        #expect(try Self.quotes(Self.citation("bob a écrit :", link: link)).first?.citedNumreponse == nil)
    }

    @Test("A header link without `href` keeps the author")
    func headerWithoutHref() throws {
        let html = #"<table class="citation"><tr><td><b class="s1"><a class="Topic">bob a écrit :</a></b></td></tr></table>"#
        #expect(try Self.quotes(html) == [MessageQuote(author: "bob", depth: 1, citedNumreponse: nil)])
    }

    @Test("Class tokens are matched whole, not as substrings")
    func classTokens() throws {
        #expect(try Self.quotes(Self.citation("bob a écrit :", tag: "citation_blacklist")).isEmpty)
        #expect(try Self.quotes(Self.citation("bob a écrit :", tag: "quoted")).isEmpty)
        #expect(try Self.quotes(Self.citation("bob a écrit :", tag: "x citation")).count == 1)
    }

    @Test("Oldcitation quotes of a real capture (R33b, not in the oracle) read author and cited number")
    func oldCitationCapture() throws {
        let html = try Fixture.capture("R33b-topic-poll-already-voted")
        let blocks = try MessageBlockParser.blocks(in: html)
        let quotes = try blocks.flatMap { try MessageQuoteAnalyzer.quotes(inContentHTML: $0.contentHTML) }
        let oldCount = html.matches(of: /class="oldcitation"/).count
        #expect(oldCount > 0 && quotes.count == oldCount)
        #expect(quotes.allSatisfy { $0.author != nil && $0.depth == 1 && $0.citedNumreponse != nil })
        #expect(quotes.first?.citedNumreponse == 933_309)
    }

    @Test("Deep nesting does not overflow the stack")
    func deepNesting() throws {
        let depth = 2_000
        let open = String(repeating: #"<table class="quote"><tr><td>"#, count: depth)
        let html = open + String(repeating: "</td></tr></table>", count: depth)
        let quotes = try Self.quotes(html)
        #expect(quotes.count == depth && quotes.last?.depth == depth)
    }
}
