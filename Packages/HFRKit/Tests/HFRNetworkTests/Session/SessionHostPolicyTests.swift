import Foundation
import Testing
@testable import HFRNetwork

struct SessionHostPolicyTests {
    private func url(_ text: String) -> URL? { URL(string: text) }

    @Test(arguments: [
        "https://forum.hardware.fr/forum1.php", "https://hardware.fr/", "http://FORUM.Hardware.FR./x", "https://a.b.hardware.fr/"
    ])
    func forumHostsAreAllowed(text: String) {
        #expect(SessionHostPolicy.forum.allows(url(text)))
    }

    @Test(arguments: [
        "https://evilhardware.fr/", "https://hardware.fr.example.com/", "https://example.com/", "ftp://forum.hardware.fr/",
        "file:///tmp/x", "https://reho.st/img.png"
    ])
    func otherHostsAreRefused(text: String) {
        #expect(!SessionHostPolicy.forum.allows(url(text)))
    }

    @Test func nilURLIsRefused() {
        #expect(!SessionHostPolicy.forum.allows(nil))
    }

    @Test func exactHostMatchesOnlyThatHost() {
        let policy = SessionHostPolicy.exactHost("127.0.0.1")
        #expect(policy.allows(url("http://127.0.0.1:8080/a")))
        #expect(!policy.allows(url("http://localhost:8080/a")))
    }

    @Test func redirectsMayNotLeaveTheForumNorDowngradeToHTTP() {
        let policy = SessionHostPolicy.forum
        let secure = url("https://forum.hardware.fr/a")
        #expect(policy.allowsRedirect(from: secure, to: url("https://forum.hardware.fr/hfr/b.htm")))
        #expect(policy.allowsRedirect(from: url("http://forum.hardware.fr/a"), to: secure))
        #expect(policy.allowsRedirect(from: url("http://forum.hardware.fr/a"), to: url("http://forum.hardware.fr/b")))
        #expect(!policy.allowsRedirect(from: secure, to: url("http://forum.hardware.fr/b")))
        #expect(!policy.allowsRedirect(from: secure, to: url("https://example.com/")))
    }
}
