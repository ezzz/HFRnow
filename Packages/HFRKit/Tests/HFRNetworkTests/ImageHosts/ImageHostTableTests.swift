import Foundation
import Testing
@testable import HFRNetwork

struct ImageHostTableTests {
    private let table = ImageHostTable.standard

    private func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test(arguments: [
        "https://reho.st/thumb/abc.png", "https://REHO.ST/x", "https://i.reho.st/x", "http://reho.st:8080/x", "https://reho.st./x"
    ])
    func rehostGetsTheForumReferer(_ text: String) throws {
        let request = try table.request(for: url(text))
        #expect(request.headers["Referer"] == "https://forum.hardware.fr")
        #expect(request.method == .get)
        #expect(request.redirectPolicy == .doNotFollow)
        #expect(request.headers["Cookie"] == nil)
    }

    /// Recognition is by parsed host at a label boundary, never by a substring of the text (LESSONS 37).
    @Test(arguments: [
        "https://reho.st.evil.example/x", "https://notreho.st/x", "https://evil.example/reho.st/x",
        "https://evil.example/?u=reho.st", "https://user@evil.example/#reho.st", "https://i.imgur.com/a.png"
    ])
    func lookalikesGetNoReferer(_ text: String) throws {
        let request = try table.request(for: url(text))
        #expect(request.headers["Referer"] == nil)
        #expect(table.rule(for: try url(text))?.referer == nil)
    }

    @Test func refusesAURLThatIsNotAbsoluteHTTP() throws {
        for text in ["ftp://reho.st/x", "file:///etc/passwd", "/thumb/x.png", "https:///x"] {
            let candidate = try #require(URL(string: text))
            #expect(throws: NetworkError.self) { try table.request(for: candidate) }
        }
    }

    @Test func httpOnlyHostsAreFlaggedWithoutRewritingTheScheme() throws {
        for text in [
            "http://img11.hostingpics.net/a.jpg", "http://nsa34.casimages.com/a.jpg", "http://panda2k3.free.fr/a.jpg",
            "http://si1.photorapide.com/a.jpg", "http://www.camif.fr/a.jpg", "http://bibi.hn.org/a.jpg"
        ] {
            let candidate = try url(text)
            #expect(table.rule(for: candidate)?.observedHTTPOnly == true, "\(text)")
            #expect(try table.request(for: candidate).url == candidate)
        }
        #expect(table.rule(for: try url("https://i.imgur.com/a.png")) == nil)
        #expect(table.rule(for: try url("http://fakehostingpics.net/a.jpg")) == nil)
        #expect(table.rule(for: try url("https://reho.st/x"))?.observedHTTPOnly == false)
    }

    @Test func thumbnailsMapToFullImages() throws {
        // The three rewrites of legacy `normalizeImageViewerURL` (`MessagesView.swift:3298-3312` @ 2440d79).
        #expect(table.fullSizeURL(for: try url("https://reho.st/thumb/ab/cd.png")).absoluteString == "https://reho.st/ab/cd.png")
        #expect(table.fullSizeURL(for: try url("https://img3.super-h.fr/images/2024/01/pic.th.jpg")).absoluteString
                == "https://img3.super-h.fr/images/2024/01/pic.jpg")
        #expect(table.fullSizeURL(for: try url("https://rehost.diberie.com/Picture/Get/t/564784")).absoluteString
                == "https://rehost.diberie.com/Picture/Get/f/564784")
        // Query and fragment survive; anything else is left alone.
        #expect(table.fullSizeURL(for: try url("https://reho.st/thumb/a.png?x=1")).absoluteString == "https://reho.st/a.png?x=1")
        for text in ["https://reho.st/a.png", "https://img3.super-h.fr/other/pic.th.jpg", "https://evil.example/thumb/a.png"] {
            #expect(table.fullSizeURL(for: try url(text)).absoluteString == text)
        }
    }

    @Test func aRuleThatWouldBuildAnInvalidPathLeavesTheURLAlone() throws {
        let broken = ImageHostTable(rules: [
            ImageHostRule(host: "img.example", thumbnailRewrite: .pathPrefix(prefix: "/thumb/", replacement: "/100%/")),
            ImageHostRule(host: "marker.example", thumbnailRewrite: .fileNameMarker(pathPrefix: "/i/", marker: "2F"))
        ])
        for text in ["https://img.example/thumb/a.png", "https://marker.example/i/a%2Fb.png"] {
            #expect(broken.fullSizeURL(for: try url(text)).absoluteString == text)
        }
    }

    @Test func nonUTF8PercentEscapesSurviveTheRewrite() throws {
        let rewritten = table.fullSizeURL(for: try url("https://reho.st/thumb/caf%E9.jpg"))
        #expect(rewritten.absoluteString == "https://reho.st/caf%E9.jpg")
    }

    @Test func extensionlessHostsAreListed() throws {
        for text in ["https://reho.st/abc", "https://img3.super-h.fr/images/x", "https://rehost.diberie.com/Picture/Get/f/1"] {
            #expect(table.servesExtensionlessImages(try url(text)), "\(text)")
        }
        #expect(!table.servesExtensionlessImages(try url("https://i.imgur.com/a")))
    }

    @Test func aRuleIsDataSoACaptureCanChangeIt() throws {
        let custom = ImageHostTable(rules: [ImageHostRule(host: "reho.st", referer: nil)])
        #expect(try custom.request(for: url("https://reho.st/x")).headers["Referer"] == nil)
        let refererWithSlash = ImageHostTable(rules: [ImageHostRule(host: "reho.st", referer: "https://forum.hardware.fr/")])
        #expect(try refererWithSlash.request(for: url("https://reho.st/x")).headers["Referer"] == "https://forum.hardware.fr/")
    }

    @Test func noRuleCarriesAKey() {
        // The table is public data and keyless by construction: the only key is `RehostConfiguration`'s.
        let mirror = Mirror(reflecting: ImageHostRule(host: "x.example"))
        #expect(!mirror.children.contains { ($0.label ?? "").lowercased().contains("key") })
    }
}
