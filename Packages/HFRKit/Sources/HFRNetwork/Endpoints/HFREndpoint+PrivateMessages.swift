import Foundation
import HFRModels

extension HFREndpoint {
    /// R60a: the first page of a private thread with its first message, the URL legacy reads the MPStorage thread with
    /// (`MPStorage.m:769-777` @ 2440d79). HFR answers it 200 without redirect (`R60a`), so a redirect is not followed:
    /// legacy's callers did not follow one either (`setShouldRedirect:NO`, `MPStorage.m:841, 943`).
    public static func privateThreadFirstPage(post: Int) throws -> HTTPRequest {
        guard post >= 1 else { throw NetworkError.invalidRequest(reason: "post must be 1 or more") }
        return try .get(
            url(path: "/forum2.php", query: [
                ("config", config), ("cat", CategoryID.privateMessages.queryValue), ("post", String(post)),
                ("numreponse", "0"), ("page", "1"), ("p", "1"), ("subcat", "0"), ("sondage", "0"), ("owntopic", "0")
            ]),
            redirectPolicy: .doNotFollow
        )
    }

    /// R45b: the new-MP composer with its recipient prefilled, the link of a profile page and of a message's MP button
    /// (`ParseMessagesOperation.m:389-390`, HFR-PROTOCOL R9).
    public static func newPrivateMessageForm(to recipient: String) throws -> HTTPRequest {
        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkError.invalidRequest(reason: "empty recipient")
        }
        return try .get(url(path: "/message.php", query: [
            ("config", config), ("cat", CategoryID.privateMessages.queryValue), ("sond", ""), ("p", "1"), ("subcat", ""),
            ("dest", recipient), ("subcatgroup", "0")
        ]))
    }
}
