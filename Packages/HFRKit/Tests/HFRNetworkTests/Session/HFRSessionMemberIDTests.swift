import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels
import Testing
@testable import HFRNetwork

/// `md_id` (#1420): the login alone sets it (`W1420a`, `W1420b`), later pages refresh `md_user` and `md_passs` only
/// (`R1420g`), and HFR answers a profile 403 without it (`R1420c`, `R1420d`). Runs against a loopback server only.
struct HFRSessionMemberIDTests {
    private static func session(_ cookies: [StoredCookie]) -> HFRSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return HFRSession(cookies: cookies, hashCheck: nil, now: Date(), configuration: configuration, hosts: .exactHost("127.0.0.1"))
    }

    private static func cookie(_ name: String, _ value: String, expires: Date? = nil) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: "127.0.0.1", path: "/", expiresDate: expires)
    }

    /// The jar a login leaves (`W1420a`: `md_user`, `md_passs`, `md_id`, each +30 days).
    private static var loginJar: [StoredCookie] {
        let expiry = Date().addingTimeInterval(30 * 86_400)
        return [cookie("md_user", "user2", expires: expiry), cookie("md_passs", "loginpass", expires: expiry),
                cookie("md_id", "900002", expires: expiry)]
    }

    @Test func aLoginJarHoldsTheMemberID() async {
        #expect(await Self.session(Self.loginJar).holdsMemberID())
    }

    /// A legacy account (LOT-067: legacy's `updateCookies:` replaced its list, dropping `md_id`, `5c0f10db`), a login past its
    /// 30 days, and HFR's logout marker hold no usable `md_id`.
    @Test(arguments: [
        [cookie("md_user", "user2"), cookie("md_passs", "pass")],
        [cookie("md_user", "user2"), cookie("md_passs", "pass"), cookie("md_id", "900002", expires: Date().addingTimeInterval(-60))],
        [cookie("md_user", "user2"), cookie("md_passs", "pass"), cookie("md_id", "deleted")],
        [cookie("md_user", "user2"), cookie("md_passs", "pass"), cookie("md_id", "")]
    ])
    func noUsableMemberID(cookies: [StoredCookie]) async {
        #expect(await !Self.session(cookies).holdsMemberID())
    }

    /// A page that refreshes the login (`R1420g`: `md_user`, `md_passs`, no `md_id`) keeps `md_id`, and the profile request
    /// that follows carries it (legacy `updateCookies:` dropped it, `5c0f10db`).
    @Test func aRefreshKeepsTheMemberIDAndTheProfileRequestCarriesIt() async throws {
        let server = try LoopbackServer { request in
            guard request.path == "/home" else { return ServerReply() }
            return ServerReply(headers: ["Set-Cookie": "md_passs=refreshed; Path=/; Max-Age=2592000"])
        }
        defer { server.stop() }
        let session = Self.session(Self.loginJar)
        _ = try await session.send(.get(server.baseURL.appending(path: "home")))
        _ = try await session.send(.get(server.baseURL.appending(path: "hfr/profil-900002.htm")))
        let header = try #require(server.requests.last { $0.path == "/hfr/profil-900002.htm" }?.headers["cookie"])
        #expect(header.contains("md_id=900002"))
        #expect(header.contains("md_passs=refreshed"))
        #expect(await session.holdsMemberID())
    }
}
