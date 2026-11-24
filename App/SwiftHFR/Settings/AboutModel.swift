import Foundation
import HFRParsing
import Observation

/// The app's version, build and git commit, as the Info.plist states them (legacy `AppSettingsView.appVersion`, `:180-184` @ 87fe0d1c).
struct AppVersion: Equatable, Sendable {
    let short: String
    let build: String
    /// Short sha the app was built from (`-dirty` with local changes), `?` when the build did not record it (#970).
    let commit: String

    /// Reads `CFBundleShortVersionString`, `CFBundleVersion` and `HFRGitCommit`; a missing, empty or non-text key is `?`.
    init(info: [String: Any]?) {
        short = Self.text(info, "CFBundleShortVersionString")
        build = Self.text(info, "CFBundleVersion")
        commit = Self.text(info, "HFRGitCommit")
    }

    private static func text(_ info: [String: Any]?, _ key: String) -> String {
        guard let value = info?[key] as? String, !value.isEmpty else { return "?" }
        return value
    }

    /// The version of the running app.
    static var current: AppVersion { AppVersion(info: Bundle.main.infoDictionary) }

    /// `1.0 (42)`.
    var display: String { "\(short) (\(build))" }

    /// `1.0 (42) · cd04954`, the commit only when known: the row never shows a lone `?` commit.
    var rowText: String { commit == "?" ? display : "\(display) · \(commit)" }
}

/// The app's own topics on the HFR forum, linked from About (operator decision 2026-10-28, issue #211). The URLs are in the
/// id form, never with a slug: a slug follows the topic title, which changes at each release (legacy `credits.html:12`
/// carries an outdated one). Both topics sit in the Apple category that is hidden from the forum list (Q-7).
enum AboutTopicLink: CaseIterable, Hashable, Sendable {
    case superHFRPlus
    case beta

    /// Row title.
    var title: String {
        switch self {
        case .superHFRPlus: "[TU] Super HFR+"
        case .beta: "Beta"
        }
    }

    /// The topic's link, as the operator gave it (`forum2.php`, category 25).
    var address: String {
        switch self {
        case .superHFRPlus: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&post=1711&page=1"
        case .beta: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&subcat=528&post=8811&page=1"
        }
    }

    /// Where the link leads, read by LOT-095's router (the only link parser, LOT-137): a topic page, never a browser.
    var target: ReaderTarget? { ReaderTarget(link: address) }
}

// Port of SuperHFRplus/Assets/HTML/credits.html (the "Mentions légales" contact block, `:7-14`) @ 87fe0d1c. Differences: rows
// of the About screen instead of a static page; the forum topic opens in the reader and the profile in the profile sheet
// (LOT-159, operator decision 2026-11-24).
/// « Nous contacter » (LOT-159, guideline 1.2 "published contact information"): legacy's two contacts, in its words.
enum AboutContact: CaseIterable, Hashable, Sendable {
    /// "Sur le forum : Topic Unique" (`credits.html:12`): the app's topic, the one `AboutTopicLink.superHFRPlus` opens.
    case forum
    /// "En privé : ezzz" (`credits.html:13`): the legacy maintainer's forum profile.
    case privately

    /// Legacy's sentence above the contacts (`credits.html:9`, accents fixed).
    static let notice = "HFR+ n'est pas développé par l'équipe du site hardware.fr, mais de manière bénévole. Pour toutes "
        + "questions, soucis, bugs, vous pouvez nous contacter :"

    /// Row title, legacy's.
    var title: String {
        switch self {
        case .forum: "Sur le forum : Topic Unique"
        case .privately: "En privé : ezzz"
        }
    }

    /// Row symbol.
    var symbol: String {
        switch self {
        case .forum: "bubble.left.and.text.bubble.right"
        case .privately: "person.crop.circle"
        }
    }

    /// The link legacy's page gave (`credits.html:12-13`); the topic in the id form of `AboutTopicLink` (no slug).
    var address: String {
        switch self {
        case .forum: AboutTopicLink.superHFRPlus.address
        case .privately: "https://forum.hardware.fr/hfr/profil-15867.htm"
        }
    }
}

// Port of HFRswift/Swift/AppSettingsView.swift (aboutSection, appVersion) @ 87fe0d1c. Differences: the topic links and their
// reader have no legacy counterpart (operator decision 2026-10-28, GAP-151, LOT-120 spec).
/// Logic of the About screen (LOT-120): the two topic links and the reader a link opens (the version row is `VersionRow`).
@Observable @MainActor
final class AboutModel {
    /// The topic whose reader is open, nil when none is.
    var selected: AboutTopicLink?
    /// The profile sheet a contact opened, nil when none is.
    var profile: UserProfileModel?

    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    private let makeProfile: @MainActor (Int) -> UserProfileModel?
    private var current: (link: AboutTopicLink, model: TopicReaderModel)?

    /// An About model over the app's topic page source; `renderOptions` are the reader's display choices, `makeProfile` the
    /// profile sheet of a member id (nil: the private contact opens nothing).
    init(
        topicPages: any TopicPageSource,
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() },
        makeProfile: @escaping @MainActor (Int) -> UserProfileModel? = { _ in nil }
    ) {
        self.topicPages = topicPages
        self.renderOptions = renderOptions
        self.makeProfile = makeProfile
    }

    /// Opens `contact`: the topic in the reader, the profile in its sheet (the member id read by LOT-095's router).
    func open(_ contact: AboutContact) {
        switch contact {
        case .forum:
            selected = .superHFRPlus
        case .privately:
            guard let url = URL(string: contact.address), case .profile(let id) = HFRLinkRoute.route(for: url) else { return }
            profile = makeProfile(id)
        }
    }

    /// The reader of `link`: the same model while the link stays selected, so a rotation does not reload the page. Nil when the
    /// router does not read the link as a topic.
    func reader(for link: AboutTopicLink) -> TopicReaderModel? {
        if let current, current.link == link { return current.model }
        guard let target = link.target else { return nil }
        let model = TopicReaderModel(target: target, title: link.title, source: topicPages, renderOptions: renderOptions)
        current = (link, model)
        return model
    }
}
