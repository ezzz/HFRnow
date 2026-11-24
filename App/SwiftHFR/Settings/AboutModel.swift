import Foundation
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

// Port of SuperHFRplus/Assets/HTML/credits.html (the "Mentions légales" contact block, `:7-12`) @ 87fe0d1c. Differences: a
// section of the About screen instead of a static page; the forum contact only, the topic opened in the reader (LOT-159,
// operator decisions of 2026-11-24 on #249: no private contact).
/// « Nous contacter » (LOT-159, guideline 1.2 "published contact information"): legacy's sentence and its forum contact.
enum AboutContact {
    /// Legacy's sentence above the contact (`credits.html:9`, accents fixed). The product name in it ("HFR+", legacy's) is the
    /// operator's call.
    static let notice = "HFR+ n'est pas développé par l'équipe du site hardware.fr, mais de manière bénévole. Pour toutes "
        + "questions, soucis, bugs, vous pouvez nous contacter :"
    /// Legacy's row title (`credits.html:12`).
    static let forumTitle = "Sur le forum : Topic Unique"
    /// The topic it opens: the app's topic, legacy's link (`credits.html:12`) in the id form of `AboutTopicLink`.
    static let forumTopic = AboutTopicLink.superHFRPlus
}

// Port of HFRswift/Swift/AppSettingsView.swift (aboutSection, appVersion) @ 87fe0d1c. Differences: the topic links and their
// reader have no legacy counterpart (operator decision 2026-10-28, GAP-151, LOT-120 spec).
/// Logic of the About screen (LOT-120): the two topic links and the reader a link opens (the version row is `VersionRow`).
@Observable @MainActor
final class AboutModel {
    /// The topic whose reader is open, nil when none is.
    var selected: AboutTopicLink?

    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    private var current: (link: AboutTopicLink, model: TopicReaderModel)?

    /// An About model over the app's topic page source; `renderOptions` are the reader's display choices.
    init(
        topicPages: any TopicPageSource,
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() }
    ) {
        self.topicPages = topicPages
        self.renderOptions = renderOptions
    }

    /// « Sur le forum : Topic Unique »: opens the app's topic in the reader (LOT-159).
    func openForumContact() {
        selected = AboutContact.forumTopic
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
