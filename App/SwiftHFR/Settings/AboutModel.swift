import Foundation
import Observation

/// The app's version and build, as the Info.plist states them (legacy `AppSettingsView.appVersion`, `:180-184` @ 87fe0d1c).
struct AppVersion: Equatable, Sendable {
    let short: String
    let build: String

    /// Reads `CFBundleShortVersionString` and `CFBundleVersion`; a missing or non-text key is `?`, as legacy.
    init(info: [String: Any]?) {
        short = info?["CFBundleShortVersionString"] as? String ?? "?"
        build = info?["CFBundleVersion"] as? String ?? "?"
    }

    /// The version of the running app.
    static var current: AppVersion { AppVersion(info: Bundle.main.infoDictionary) }

    /// `1.0 (42)`.
    var display: String { "\(short) (\(build))" }
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

// Port of HFRswift/Swift/AppSettingsView.swift (aboutSection, appVersion) @ 87fe0d1c. Differences: the topic links and their
// reader have no legacy counterpart (operator decision 2026-10-28, GAP-151, LOT-120 spec).
/// Logic of the About screen (LOT-120): the version, the two topic links and the reader a link opens.
@Observable @MainActor
final class AboutModel {
    /// The version row.
    let version: AppVersion
    /// The topic whose reader is open, nil when none is.
    var selected: AboutTopicLink?

    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    private var current: (link: AboutTopicLink, model: TopicReaderModel)?

    /// An About model over the app's topic page source; `renderOptions` are the reader's display choices.
    init(
        version: AppVersion = .current, topicPages: any TopicPageSource,
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() }
    ) {
        self.version = version
        self.topicPages = topicPages
        self.renderOptions = renderOptions
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
