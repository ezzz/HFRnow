import Foundation
import HFRModels
import HFRParsing

/// What a tap in the page opens: a link or a video. Moved out of the model file, which is at its length limit.
extension TopicReaderModel {
    /// What tapping `url` does. Topic and private message links of the forum, as LOT-095's router reads them, open in the
    /// app at their page and post (issue #106); other web links open in the browser `defaultBrowser` names (legacy
    /// `MessagesView.swift:3963-3968` at `21173e77`). A forum page the router sends elsewhere (a list, a profile, a page
    /// view it does not own) opens in the browser too, never in the reader with the session; a profile opens the profile
    /// sheet (LOT-116), which fetches it without cookies.
    func action(forLink url: URL, defaultBrowser: Bool) -> ReaderLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        if let target = ReaderTarget(link: url.absoluteString) { return .reader(target) }
        if case .profile(let memberID) = HFRLinkRoute.route(for: url) { return .profile(memberID: memberID) }
        return defaultBrowser ? .defaultBrowser(url) : .inAppBrowser(url)
    }

    /// The video `index` of message `post` on the page shown, for the player opened on tap (D-071-2).
    func video(post: Int, index: Int, token: Int) -> MessageEmbed? {
        guard token == document?.token, let message = page?.messages.first(where: { $0.numreponse == post }),
              message.content.embeds.indices.contains(index) else { return nil }
        return message.content.embeds[index]
    }
}
