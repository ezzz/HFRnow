import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing

/// The two forum lookups of the smiley panel (LOT-053): `SmileyLookupFlow` in the app, a scripted double in tests.
protocol SmileyLookups: Sendable {
    /// Same contract as `SmileyLookupFlow.search(_:requireAll:)`.
    func search(_ text: String, requireAll: Bool) async throws(SmileyLookupError) -> [ForumSmiley]
    /// Same contract as `SmileyLookupFlow.wiki(code:)`.
    func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail
    /// Same contract as `OwnSmileysFlow.load()`. The default is none, for doubles that do not script it.
    func ownSmileys() async throws(SmileyLookupError) -> [OwnSmiley]
}

extension SmileyLookups {
    func ownSmileys() async throws(SmileyLookupError) -> [OwnSmiley] { [] }
}

/// LOT-053's flow over the current account's session (the search carries its cookies, the wiki none).
struct LiveSmileyLookups: SmileyLookups {
    let flow: SmileyLookupFlow
    let own: OwnSmileysFlow

    /// A lookup over `session`.
    init(session: HFRSession) {
        flow = SmileyLookupFlow(session: session)
        own = OwnSmileysFlow(session: session)
    }

    func search(_ text: String, requireAll: Bool) async throws(SmileyLookupError) -> [ForumSmiley] {
        try await flow.search(text, requireAll: requireAll)
    }

    func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail {
        try await flow.wiki(code: code)
    }

    func ownSmileys() async throws(SmileyLookupError) -> [OwnSmiley] {
        try await own.load()
    }
}
