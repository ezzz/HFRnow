import Foundation
import Testing
@testable import HFRNetwork

struct FormBodyTests {
    @Test(arguments: [
        ("é", "%C3%A9"),
        ("à la carte", "%C3%A0+la+carte"),
        ("a&b", "a%26b"),
        ("a+b", "a%2Bb"),
        ("a=b", "a%3Db"),
        ("a?b", "a%3Fb"),
        ("100%", "100%25"),
        ("x y", "x+y"),
        ("Se connecter", "Se+connecter"),
        ("*-._", "*-._"),
        ("~!'()", "%7E%21%27%28%29"),
        ("€", "%E2%82%AC"),
        ("日本", "%E6%97%A5%E6%9C%AC"),
        ("", "")
    ])
    func encodesValue(input: String, expected: String) {
        #expect(FormBody([("k", input)]).encodedString == "k=\(expected)")
    }

    @Test func keepsFieldOrderAndEncodesNames() {
        var body = FormBody([("hash_check", "abc"), ("cat", "13")])
        body.append("é&", "1")
        #expect(body.encodedString == "hash_check=abc&cat=13&%C3%A9%26=1")
        #expect(body.data == Data("hash_check=abc&cat=13&%C3%A9%26=1".utf8))
    }

    @Test func emptyBodyIsEmpty() {
        #expect(FormBody().encodedString.isEmpty)
    }

    @Test func preserveKeepsLineBreaksAsGiven() {
        let body = FormBody([("m", "a\nb\r\nc\rd")])
        #expect(body.encodedString == "m=a%0Ab%0D%0Ac%0Dd")
    }

    @Test func crlfModeNormalisesEveryLineBreak() {
        let body = FormBody([("m", "a\nb\r\nc\rd")], newlines: .crlf)
        #expect(body.encodedString == "m=a%0D%0Ab%0D%0Ac%0D%0Ad")
    }

    @Test func postRequestCarriesContentTypeAndBody() throws {
        let url = try #require(URL(string: "https://forum.hardware.fr/bddpost.php"))
        let request = HTTPRequest.post(url, form: FormBody([("content_form", "é")]))
        #expect(request.method == .post)
        #expect(request.headers["content-type"] == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(request.body == Data("content_form=%C3%A9".utf8))
    }
}
