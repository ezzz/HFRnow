import HFRModels
import Testing
@testable import HFRParsing

/// #875: the `subcat` of a sub-forum is read from the page's own "new topic" link.
@Suite("Sub-forum target (#875)")
struct SubforumTargetTests {
    @Test("A sub-forum page names its category and subcat", arguments: [
        ("R603d-list-subcat-owntopic3", 432, "/hfr/Discussions/Viepratique/liste_sujet-1.htm"),
        ("R06-list-subcat-cuisine-anon", 433, "/hfr/Discussions/Cuisine/liste_sujet-1.htm")
    ])
    func subforumPage(capture: String, subcat: Int, pageURL: String) throws {
        let page = try TopicListParser.parse(try Fixture.capture(capture), pageURL: pageURL)
        #expect(SubforumTarget(newTopicPath: page.newTopicPath) == SubforumTarget(category: .forum(13), subcategory: subcat))
    }

    @Test("A category page has none")
    func categoryPage() throws {
        let html = try Fixture.capture("R09-list-cat13-owntopic3-anon")
        let page = try TopicListParser.parse(html, pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        #expect(SubforumTarget(newTopicPath: page.newTopicPath) == nil)
    }

    @Test("Missing, empty or non-numeric values give nothing", arguments: [
        nil, "", "/message.php?config=hfr.inc&cat=13&subcat=", "/message.php?cat=13&subcat=0", "/message.php?subcat=5",
        "/message.php?cat=x&subcat=5"
    ] as [String?])
    func noTarget(path: String?) {
        #expect(SubforumTarget(newTopicPath: path) == nil)
    }
}
