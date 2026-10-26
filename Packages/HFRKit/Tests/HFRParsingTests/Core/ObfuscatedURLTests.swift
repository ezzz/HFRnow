import Foundation
import Testing
@testable import HFRParsing

@Suite("Obfuscated URL decoder")
struct ObfuscatedURLTests {
    /// Payloads computed independently of `encode` (Python, alphabet `0A12B34C56D78E9F`).
    static let knownVectors: [(payload: String, url: String)] = [
        (
            "1F444FC1C34E2119C045C02F424F4944464C2E4544C11946494214424ACB2E2A2214C04FC2CB2E2B2114C04A4C432E22",
            "/forum2.php?config=hfr.inc&cat=13&post=42&page=3"
        ),
        (
            "1F4E43C2C24A4C4319C045C02F424F4944464C2E4544C11946494214424ACB2E2A2214C04FC2CB2E2B211449C34EC143C02E2A20202A14C143442E2C",
            "/message.php?config=hfr.inc&cat=13&post=42&numrep=1001&ref=7"
        ),
        ("1F4544C11FBB46C242C3C2C2464F49C21F4246CB43C11E2A221E2A20202A1E221E2C1945CB4E", "/hfr/Discussions/citer-13-1001-3-7.htm"),
        ("82D6", "é")
    ]

    @Test("Decodes known payloads behind each of the three prefixes", arguments: ObfuscatedURLPrefix.allCases)
    func decodesKnownVectors(prefix: ObfuscatedURLPrefix) {
        for vector in Self.knownVectors {
            #expect(ObfuscatedURL.decode(classAttribute: prefix.rawValue + vector.payload) == vector.url)
        }
    }

    @Test("Prefix lengths match HFR-PROTOCOL §4")
    func prefixLengths() {
        #expect(ObfuscatedURLPrefix.noClass.rawValue.count == 20)
        #expect(ObfuscatedURLPrefix.blank.rawValue.count == 18)
        #expect(ObfuscatedURLPrefix.plain.rawValue.count == 12)
    }

    @Test("Encoding matches the known vectors", arguments: ObfuscatedURLPrefix.allCases)
    func encodesKnownVectors(prefix: ObfuscatedURLPrefix) {
        for vector in Self.knownVectors {
            #expect(ObfuscatedURL.encode(vector.url, prefix: prefix) == prefix.rawValue + vector.payload)
        }
    }

    @Test(
        "Round trip encode then decode",
        arguments: [
            "/forum2.php?config=hfr.inc&cat=prive&post=7&page=1",
            "/hfr/Hardware/editer-3-555-12.htm",
            "/user/modo.php?config=hfr.inc&cat=13&post=1&numreponse=99",
            "/message.php?config=hfr.inc&cat=13&post=42&numrep=1&ref=2&titre=Café crème",
            "a"
        ]
    )
    func roundTrip(url: String) {
        for prefix in ObfuscatedURLPrefix.allCases {
            #expect(ObfuscatedURL.decode(classAttribute: ObfuscatedURL.encode(url, prefix: prefix)) == url)
        }
    }

    @Test("Finds the prefixed token among other classes")
    func otherClassTokens() {
        let payload = Self.knownVectors[0].payload
        let expected = Self.knownVectors[0].url
        #expect(ObfuscatedURL.decode(classAttribute: "cLink md_cryptlink\(payload)") == expected)
        #expect(ObfuscatedURL.decode(classAttribute: "  md_noclass_cryptlink\(payload)\tright ") == expected)
        #expect(ObfuscatedURL.decode(classAttribute: "a\u{0C}md_cryptlink\(payload)\r\nb") == expected)   // form feed, CR, LF split
    }

    @Test(
        "Skip rules: nothing to decode",
        arguments: [
            "",
            "md_cryptlink",                                      // length == prefix
            "md_noclass_cryptlink",
            "md_blank_cryptlink",
            "cLink right",                                       // no prefix
            "/forum2.php?config=hfr.inc&cat=13",                 // link in clear (`/`)
            "md_cryptlink1F44 /x",                               // contains `/`
            "md_cryptlink1F44http",                              // contains `http`
            "md_cryptlink1F44HTTP",
            "md_cryptlink1F4",                                   // odd length
            "md_cryptlink1G44",                                  // outside the alphabet
            "md_cryptlink1f44",                                  // lowercase is outside the alphabet
            "md_cryptlinkFF",                                    // byte 0xFF is not UTF-8
            "xmd_cryptlink1F44",                                 // prefix not at token start
            "x\u{00A0}md_cryptlink1F44",                         // U+00A0 does not split HTML class tokens
            "x\u{2003}md_cryptlink1F44"
        ]
    )
    func skipRules(raw: String) {
        #expect(ObfuscatedURL.decode(classAttribute: raw) == nil)
    }

    @Test("Resolved URL: obfuscated values are decoded then made absolute")
    func resolvedObfuscated() {
        let raw = "md_noclass_cryptlink" + Self.knownVectors[2].payload
        #expect(ObfuscatedURL.resolvedURL(from: raw)?.absoluteString == "https://forum.hardware.fr/hfr/Discussions/citer-13-1001-3-7.htm")
    }

    @Test("Resolved URL: links in clear are made absolute unchanged")
    func resolvedClear() {
        #expect(
            ObfuscatedURL.resolvedURL(from: "/forum2.php?config=hfr.inc&amp;cat=13")?.absoluteString
                == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13"
        )
    }

    @Test(
        "Resolved URL: a marked value that does not decode gives nil, not a URL built from the class",
        arguments: [
            "md_cryptlink", "md_cryptlink1G", "md_noclass_cryptlinkZZZZ", "md_cryptlink1F44 http",
            "\u{00A0}md_cryptlink1F44"   // U+00A0 is part of the token, not trimmed as HTML whitespace
        ]
    )
    func resolvedUndecodable(raw: String) {
        #expect(ObfuscatedURL.resolvedURL(from: raw) == nil)
    }

    @Test("Resolved URL: a decoded javascript: link is refused")
    func resolvedRejectsScheme() {
        let raw = "md_cryptlink" + "4D4AC44AC242C146C0CB2D4A4843C1CB152A16"
        #expect(ObfuscatedURL.decode(classAttribute: raw) == "javascript:alert(1)")
        #expect(ObfuscatedURL.resolvedURL(from: raw) == nil)
    }
}
