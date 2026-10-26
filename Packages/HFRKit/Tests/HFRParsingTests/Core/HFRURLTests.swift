import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// URL shapes come from HFR-PROTOCOL §1–§4 and the redface2 research §4.3 (E7, E13, E20); ids are invented.
@Suite("HFR URL helpers")
struct HFRURLTests {
    // MARK: - Absolutization

    /// Forum-relative paths of every read and write endpoint (HFR-PROTOCOL R1–R9, S1, S3, §3), `&amp;` already decoded.
    @Test(
        "Root-relative forum paths get the forum origin",
        arguments: [
            "/",
            "/forum1.php?config=hfr.inc&cat=13&page=2&subcat=&owntopic=0",
            "/forum1f.php?owntopic=3",
            "/forum1.php?config=hfr.inc&cat=prive&page=1",
            "/forum2.php?config=hfr.inc&cat=13&post=42&page=3",
            "/hfr/Discussions/Sujet-exemple-sujet_42_3.htm#t1001",
            "/hfr/Discussions/citer-13-1001-3-7.htm",
            "/user/editprofil.php?config=hfr.inc&page=5",
            "/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2",
            "/hfr/profil-12345.htm",
            "/search.php?config=hardwarefr.inc",
            "/transsearch.php",
            "/bddpost.php?config=hfr.inc",
            "/user/modo.php?config=hfr.inc&cat=13&post=42&numreponse=1001",
            "/message.php?config=hfr.inc&cat=prive&dest="
        ]
    )
    func rootRelative(path: String) {
        #expect(HFRURL.absolute(path)?.absoluteString == "https://forum.hardware.fr" + path)
    }

    @Test(
        "Absolute URL for other link forms",
        arguments: [
            ("/forum2.php?config=hfr.inc&amp;cat=13&amp;post=42", "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42"),
            ("forum2.php?config=hfr.inc&cat=13&post=42", "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42"),
            ("//forum-images.hardware.fr/icones/smile.gif", "https://forum-images.hardware.fr/icones/smile.gif"),
            ("http://forum.hardware.fr/forum2.php?post=1", "https://forum.hardware.fr/forum2.php?post=1"),   // forum upgraded
            ("HTTP://Forum.Hardware.fr/x", "https://forum.hardware.fr/x"),                             // host lowercased
            ("https://Example.ORG/Path", "https://example.org/Path"),
            ("http://forum.hardware.fr:8080/x", "http://forum.hardware.fr:8080/x"),                    // port blocks upgrade
            ("https://forum.hardware.fr:443/x", "https://forum.hardware.fr:443/x"),
            ("http://example.org/image.png", "http://example.org/image.png"),                          // other hosts kept
            ("https://example.org/a?b=1&amp;c=2", "https://example.org/a?b=1&c=2"),
            ("  /forum2.php?post=1 \n", "https://forum.hardware.fr/forum2.php?post=1")
        ]
    )
    func absolute(raw: String, expected: String) {
        #expect(HFRURL.absolute(raw)?.absoluteString == expected)
    }

    @Test(
        "Absolute URL refuses empty values and non-web schemes",
        arguments: [
            "", "   ", "javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:alert(1)",
            "java\nscript:alert(1)", "java\tscript:alert(1)", "data:text/html;base64,AAAA", "file:///etc/hosts",
            "blob:https://forum.hardware.fr/x", "mailto:someone@example.org", "https://", "//",
            "https://forum.hardware.fr@evil.example/x", "https://user:secret@forum.hardware.fr/x",   // user info
            "//forum.hardware.fr@evil.example/x", "http://user@forum.hardware.fr/x"
        ]
    )
    func absoluteRefuses(raw: String) {
        #expect(HFRURL.absolute(raw) == nil)
    }

    @Test("Tabs and newlines inside a link are removed, as browsers do")
    func removesTabsAndNewlines() {
        #expect(HFRURL.absolute("/forum2.php?config=hfr.inc&\ncat=13&\tpost=42")?.absoluteString
            == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42")
    }

    /// Platforms differ on whether such a string is a valid relative reference; either way it must not become a script URL.
    @Test(
        "A percent-encoded scheme is never decoded into one",
        arguments: ["%6Aavascript:alert(1)", "%6A%61vascript:alert(1)", "javascript%3Aalert(1)"]
    )
    func percentEncodedScheme(raw: String) {
        let url = HFRURL.absolute(raw)
        #expect(url == nil || (url?.scheme == "https" && url?.host == "forum.hardware.fr"))
    }

    @Test("Relative links resolve against the given page")
    func relativeToPage() throws {
        let page = try #require(URL(string: "https://forum.hardware.fr/hfr/Discussions/Sujet-sujet_42_3.htm"))
        #expect(HFRURL.absolute("Sujet-sujet_42_4.htm", relativeTo: page)?.absoluteString
            == "https://forum.hardware.fr/hfr/Discussions/Sujet-sujet_42_4.htm")
        #expect(HFRURL.absolute("/forum2.php?post=42", relativeTo: page)?.absoluteString == "https://forum.hardware.fr/forum2.php?post=42")
    }

    // MARK: - Query values

    @Test("Query values are matched by exact name, percent-decoded, after &amp;")
    func queryValues() {
        let link = "/forum2.php?config=hfr.inc&amp;subpage=9&amp;cat=13&amp;post=42&amp;page=3&amp;word=caf%C3%A9&amp;empty="
        #expect(HFRURL.queryValue(named: "page", in: link) == "3")
        #expect(HFRURL.queryValue(named: "subpage", in: link) == "9")
        #expect(HFRURL.queryValue(named: "word", in: link) == "café")
        #expect(HFRURL.queryValue(named: "empty", in: link) == "")
        #expect(HFRURL.queryValue(named: "missing", in: link) == nil)
        #expect(HFRURL.queryValue(named: "page", in: "/forum2.php#page=3") == nil)   // fragment is not query
        #expect(HFRURL.queryValue(named: "config", in: "/forum2.php?config") == "")
        #expect(HFRURL.queryValue(named: "findsmilies", in: "/message-smi-mp-aj.php?findsmilies=+w1+w2") == "+w1+w2")  // `+` kept
    }

    // MARK: - Page

    @Test(
        "Page number for every link shape",
        arguments: [
            ("/forum1.php?config=hfr.inc&cat=13&page=2&subcat=&owntopic=0", 2),
            ("/forum1.php?config=hfr.inc&cat=prive&page=4", 4),
            ("/forum2.php?config=hfr.inc&amp;cat=13&amp;post=42&amp;page=57", 57),
            ("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=3&p=1#t1001", 3),
            ("/hfr/Discussions/Sujet-exemple-sujet_42_450.htm", 450),
            ("/hfr/Discussions/Sujet-exemple-sujet_42_450.htm#t1001", 450),
            ("/hfr/Discussions/Sous/Sujet-exemple-sujet_42_7.htm#bas", 7),
            ("/hfr/Discussions/Sous/sujet-exemple_42_9.htm", 9),          // older legacy shape
            ("/forum2.php?subpage=8&page=0&post=42_6.htm", nil as Int?),  // `subpage` and page 0 ignored, `_6.htm` is query
            ("/forum2.php?subpage=8", nil),
            ("/forum2.php?page=abc", nil),
            ("/hfr/profil-12345.htm", nil),
            ("", nil)
        ]
    )
    func page(raw: String, expected: Int?) {
        #expect(HFRURL.page(in: raw) == expected)
    }

    @Test("Query page wins over the path")
    func queryPageWins() {
        #expect(HFRURL.page(in: "/hfr/Discussions/Sujet-sujet_42_3.htm?page=5") == 5)
    }

    // MARK: - Canonical path, topic, category

    @Test("Canonical topic path R5 / E13")
    func canonical() {
        #expect(HFRURL.canonicalTopicPath(in: "/hfr/Discussions/Sujet-exemple-sujet_1711_450.htm")
            == CanonicalTopicPath(topic: 1711, page: 450))
        #expect(HFRURL.canonicalTopicPath(in: "/hfr/Hardware/Sous/Sujet-sujet_42_1.htm#t9")
            == CanonicalTopicPath(topic: 42, page: 1))
        #expect(HFRURL.canonicalTopicPath(in: "/hfr/Discussions/sujet-exemple_42_9.htm") == nil)
        #expect(HFRURL.canonicalTopicPath(in: "/hfr/Discussions/Sujet-sujet_0_3.htm") == nil)
        #expect(HFRURL.canonicalTopicPath(in: "/forum2.php?post=42&page=3") == nil)
        #expect(HFRURL.canonicalTopicPath(in: "/x?y=sujet_1_2.htm") == nil)
        #expect(HFRURL.canonicalTopicPath(in: "https://forum.hardware.fr/hfr/Discussions/Sujet-sujet_42_3.htm")
            == CanonicalTopicPath(topic: 42, page: 3))
        #expect(HFRURL.canonicalTopicPath(in: "//forum.hardware.fr/hfr/Discussions/Sous/Sujet-sujet_42_3.htm?x=1#t5")
            == CanonicalTopicPath(topic: 42, page: 3))
    }

    @Test(
        "Only the full canonical shape is canonical",
        arguments: [
            "/x/sujet_42_3.htm",                      // no `/hfr/<cat>/`
            "/x/Sujet-sujet_42_3.htm",
            "/hfr/Sujet-sujet_42_3.htm",              // no category segment
            "/hfr/Discussions/sujet_42_3.htm",        // no slug
            "/nothfr/Discussions/Sujet-sujet_42_3.htm",
            "/other/hfr/Discussions/Sujet-sujet_42_3.htm",  // segments before `/hfr/`
            "/hfr/Discussions/Sous/Autre/Sujet-sujet_42_3.htm", // two subcategories
            "https://example.org/other/hfr/Discussions/Sujet-sujet_42_3.htm",
            "Discussions/Sujet-sujet_42_3.htm"             // relative, not from the root
        ]
    )
    func notCanonical(path: String) {
        #expect(HFRURL.canonicalTopicPath(in: path) == nil)
        #expect(HFRURL.topicNumber(in: path) == nil)
        #expect(HFRURL.page(in: path) == 3)           // the older `_<page>.htm` fallback still reads the page
    }

    @Test(
        "Category from `cat=`",
        arguments: [
            ("/forum2.php?config=hfr.inc&cat=13&post=42", CategoryID.forum(13) as CategoryID?),
            ("/forum1.php?config=hfr.inc&amp;cat=prive&amp;page=1", .privateMessages),
            ("/forum1.php?config=hfr.inc&subcat=13", nil),
            ("/forum1.php?cat=-1", nil),
            ("/hfr/Discussions/Sujet-sujet_42_3.htm", nil)
        ]
    )
    func category(raw: String, expected: CategoryID?) {
        #expect(HFRURL.category(in: raw) == expected)
    }

    @Test("Topic number and identity")
    func topic() {
        #expect(HFRURL.topicNumber(in: "/forum2.php?config=hfr.inc&cat=13&post=42&page=3") == 42)
        #expect(HFRURL.topicNumber(in: "/hfr/Discussions/Sujet-sujet_1711_450.htm") == 1711)
        #expect(HFRURL.topicNumber(in: "/forum2.php?config=hfr.inc&cat=13&postx=42") == nil)
        #expect(HFRURL.topicID(in: "/forum2.php?config=hfr.inc&amp;cat=prive&amp;post=7")
            == TopicID(category: .privateMessages, topic: 7))
        #expect(HFRURL.topicID(in: "/hfr/Discussions/Sujet-sujet_1711_450.htm") == nil)   // slug is not a category id
    }

    // MARK: - Messages

    @Test("numreponse: positive only, 0 means none")
    func numreponse() {
        #expect(HFRURL.numreponse(in: "/forum2.php?config=hfr.inc&cat=13&post=42&numreponse=1001&quote_only=1") == 1001)
        #expect(HFRURL.numreponse(in: "/forum2.php?config=hfr.inc&cat=13&post=42&numreponse=0#t1001") == nil)
        #expect(HFRURL.numreponse(in: "/message.php?config=hfr.inc&cat=13&post=42&numrep=1001") == nil)
    }

    @Test("Anchor post number from `#t<id>`")
    func anchor() {
        #expect(HFRURL.anchorPostNumber(in: "/hfr/Discussions/Sujet-sujet_42_3.htm#t1001") == 1001)
        #expect(HFRURL.anchorPostNumber(in: "/forum2.php?numreponse=0#t1001") == 1001)
        #expect(HFRURL.anchorPostNumber(in: "/hfr/Discussions/Sujet-sujet_42_3.htm#bas") == nil)
        #expect(HFRURL.anchorPostNumber(in: "/hfr/Discussions/Sujet-sujet_42_3.htm#t") == nil)
        #expect(HFRURL.anchorPostNumber(in: "/hfr/Discussions/Sujet-sujet_42_3.htm#t12x") == nil)
        #expect(HFRURL.anchorPostNumber(in: "/forum2.php?post=42") == nil)
    }

    @Test(
        "Removing the anchor",
        arguments: [
            ("/hfr/Discussions/Sujet-sujet_42_3.htm#t1001", "/hfr/Discussions/Sujet-sujet_42_3.htm"),
            ("/forum2.php?post=42#bas", "/forum2.php?post=42"),
            ("/forum2.php?post=42#", "/forum2.php?post=42"),
            ("/forum2.php?post=42", "/forum2.php?post=42")
        ]
    )
    func removingAnchor(raw: String, expected: String) {
        #expect(HFRURL.removingAnchor(raw) == expected)
    }

    // MARK: - Page replacement

    @Test(
        "Replacing the page",
        arguments: [
            ("/forum2.php?config=hfr.inc&cat=13&post=42&page=3&p=1#t1001", "/forum2.php?config=hfr.inc&cat=13&post=42&page=9&p=1"),
            ("/forum2.php?config=hfr.inc&amp;subpage=2&amp;page=3", "/forum2.php?config=hfr.inc&subpage=2&page=9"),
            ("/forum1.php?config=hfr.inc&cat=13&page=&subcat=", "/forum1.php?config=hfr.inc&cat=13&page=9&subcat="),
            ("/hfr/Discussions/Sujet-exemple-sujet_42_450.htm#t1001", "/hfr/Discussions/Sujet-exemple-sujet_42_9.htm"),
            ("/hfr/Discussions/Sous/sujet-exemple_42_3.htm", "/hfr/Discussions/Sous/sujet-exemple_42_9.htm"),
            ("/forum2.php?config=hfr.inc&cat=13&post=42", "/forum2.php?config=hfr.inc&cat=13&post=42&page=9"),
            ("/forum2.php", "/forum2.php?page=9"),
            ("/forum2.php?", "/forum2.php?page=9")
        ]
    )
    func replacingPage(raw: String, expected: String) {
        #expect(HFRURL.replacingPage(in: raw, with: 9) == expected)
    }

    @Test("Replacing the page of an absolute canonical URL keeps scheme and host")
    func replacingPageAbsolute() {
        #expect(HFRURL.replacingPage(in: "https://forum.hardware.fr/hfr/Discussions/Sujet-sujet_42_3.htm#t1", with: 9)
            == "https://forum.hardware.fr/hfr/Discussions/Sujet-sujet_42_9.htm")
        #expect(HFRURL.replacingPage(in: "/other/hfr/Discussions/Sujet-sujet_42_3.htm", with: 9)
            == "/other/hfr/Discussions/Sujet-sujet_42_9.htm")   // not canonical: older `_<page>.htm` rule
    }

    @Test("Replacing the page refuses pages below 1")
    func replacingPageRefusesZero() {
        #expect(HFRURL.replacingPage(in: "/forum2.php?page=3", with: 0) == nil)
        #expect(HFRURL.replacingPage(in: "/forum2.php?page=3", with: -1) == nil)
    }

    @Test("Replacing then reading the page round-trips on every shape")
    func replaceThenRead() {
        for link in ["/forum2.php?post=42&page=3", "/hfr/Discussions/Sujet-sujet_42_3.htm", "/forum2.php?post=42"] {
            let replaced = HFRURL.replacingPage(in: link, with: 12) ?? ""
            #expect(HFRURL.page(in: replaced) == 12)
        }
    }
}
