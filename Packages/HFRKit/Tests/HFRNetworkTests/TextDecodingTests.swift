import Foundation
import Testing
@testable import HFRNetwork

struct TextDecodingTests {
    @Test func decodesValidUTF8() {
        let result = TextDecoding.decode(Data("Café — ok".utf8), contentType: "text/html; charset=utf-8")
        #expect(result == DecodedText(text: "Café — ok", encoding: .utf8))
    }

    @Test func decodesUTF8WithoutDeclarationAndStripsBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("é".utf8)
        #expect(TextDecoding.decode(data, contentType: nil) == DecodedText(text: "é", encoding: .utf8))
    }

    @Test func declaredLatin1IsReadAsWindows1252() {
        let data = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x80, 0x93])  // "café €“"
        let result = TextDecoding.decode(data, contentType: "text/html; charset=ISO-8859-1")
        #expect(result == DecodedText(text: "café €“", encoding: .windows1252))
    }

    @Test func strayByteInUTF8PageKeepsAccentsAndReplacesOnlyTheBadByte() {
        let data = Data("é ".utf8) + Data([0xFF]) + Data(" è".utf8)
        let result = TextDecoding.decode(data, contentType: "text/html; charset=utf-8")
        #expect(result.encoding == .utf8Lossy)
        #expect(result.text == "é \u{FFFD} è")
    }

    @Test func undeclaredLatin1FallsBackToWindows1252() {
        let result = TextDecoding.decode(Data([0x65, 0xE9, 0xE8]), contentType: nil)
        #expect(result == DecodedText(text: "eéè", encoding: .windows1252))
    }

    @Test func emptyBodyDecodesToEmptyString() {
        #expect(TextDecoding.decode(Data(), contentType: nil).text.isEmpty)
    }

    @Test(arguments: [
        ("text/html; charset=utf-8", "utf-8"),
        ("text/html;charset=\"ISO-8859-1\"", "iso-8859-1"),
        ("text/html; Charset = UTF-8 ", "utf-8"),
        ("text/html", nil),
        ("text/html; charset=", nil)
    ] as [(String, String?)])
    func parsesContentTypeCharset(header: String, expected: String?) {
        #expect(TextDecoding.charset(fromContentType: header) == expected)
    }

    @Test func metaCharsetIsUsedWhenHeaderHasNone() {
        let html = Data("<html><head><meta charset=ISO-8859-1></head><body>caf".utf8) + Data([0xE9])
        let result = TextDecoding.decode(html, contentType: "text/html")
        #expect(result.encoding == .windows1252)
        #expect(result.text.hasSuffix("café"))
    }

    @Test func headerWinsOverMeta() {
        let html = Data("<meta charset=iso-8859-1>é".utf8)
        let result = TextDecoding.decode(html, contentType: "text/html; charset=utf-8")
        #expect(result.encoding == .utf8)
        #expect(result.text.hasSuffix("é"))
    }

    @Test func responseDecodesWithItsOwnContentType() throws {
        let url = try #require(URL(string: "https://forum.hardware.fr/"))
        let headers: HTTPHeaders = ["content-type": "text/html; charset=iso-8859-1"]
        let response = HTTPResponse(statusCode: 200, headers: headers, url: url, body: Data([0xE9]))
        #expect(response.decodedText().text == "é")
    }
}
