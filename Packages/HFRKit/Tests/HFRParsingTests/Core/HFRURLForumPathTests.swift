import Testing
@testable import HFRParsing

/// Links a list parser may emit as paths the app requests with the account session (LESSONS 37).
@Suite("Forum-relative paths")
struct HFRURLForumPathTests {
    @Test("Forum links become forum-relative paths", arguments: [
        ("/hfr/Discussions/liste_sujet-2.htm", "/hfr/Discussions/liste_sujet-2.htm"),
        ("/forum2.php?config=hfr.inc&amp;cat=13&amp;post=1#t2", "/forum2.php?config=hfr.inc&cat=13&post=1#t2"),
        ("  /forum1.php?cat=prive\n", "/forum1.php?cat=prive"),
        ("forum2.php?cat=13&post=1", "/forum2.php?cat=13&post=1"),
        ("https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm", "/hfr/ia/liste_sujet-1.htm"),
        ("https://FORUM.hardware.fr:443/forum1.php?cat=1", "/forum1.php?cat=1"),
        ("http://forum.hardware.fr/forum1.php?cat=1#bas", "/forum1.php?cat=1#bas"),
        ("https://forum.hardware.fr", "/"),
        // A backslash after the origin is percent-encoded by `URL`, so it cannot start an authority.
        ("https://forum.hardware.fr/\\evil.example/x", "/%5Cevil.example/x")
    ])
    func accepted(raw: String, path: String) {
        #expect(HFRURL.forumRelativePath(raw) == path)
    }

    @Test("Anything that would leave the forum or not be a page is refused", arguments: [
        "", "   ", "javascript:alert(1)", "JaVaScRiPt:alert(1)", "data:text/html,x", "mailto:a@b.c",
        "//evil.example/x", "/\\evil.example/x", "https://evil.example/hfr/x.htm",
        "https://forum.hardware.fr@evil.example/", "https://user@forum.hardware.fr/",
        "http://forum.hardware.fr:80/forum1.php", "https://forum.hardware.fr:8443/x", "/x\u{0}y", "/x\ny",
        "https://forum.hardware.fr//evil.example/x"
    ])
    func refused(raw: String) {
        #expect(HFRURL.forumRelativePath(raw) == nil)
    }
}
