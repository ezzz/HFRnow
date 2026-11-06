import HFRModels
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift ("Sujets" section, GAP-052/054/071: `theme_style`, `display_sig`;
// `topic_page_swipe_navigation` from `master` @21173e7:479) @ 2440d79. Differences: the swipe key is newer than 2440d79;
// the other "Sujets" rows belong to LOT-118 (blacklist); the "Bouton +" row is LOT-086's; the smiley size stays dropped
// (commented out in legacy, LOT-119 table).

/// The reader display rows of "Sujets": each property reads its legacy key at creation and writes it back on every change
/// (LOT-106). The open reader picks the change up from the store, see `TopicReaderModel.applyDisplaySettings()`.
@MainActor
@Observable
final class TopicsSettingsModel {
    /// Message layout (`theme_style`).
    var messageStyle: ThemeStyle {
        didSet { if messageStyle != oldValue { store.set(messageStyle, for: SettingKey.themeStyle) } }
    }
    /// Show each message's signature (`display_sig`).
    var showsSignatures: Bool {
        didSet { if showsSignatures != oldValue { store.set(showsSignatures, for: SettingKey.displaySignatures) } }
    }
    /// A horizontal swipe changes the reader's page (`topic_page_swipe_navigation`).
    var swipesPages: Bool {
        didSet { if swipesPages != oldValue { store.set(swipesPages, for: SettingKey.topicPageSwipe) } }
    }

    /// What the reader's "+" button does (`reply_button_behavior`, LOT-086).
    var replyButton: ReplyButtonBehavior {
        didSet { if replyButton != oldValue { store.set(replyButton, for: SettingKey.replyButtonBehavior) } }
    }

    @ObservationIgnored private let store: any SettingsStore

    /// Reads the current values from `store`; creating it writes nothing.
    init(store: any SettingsStore) {
        self.store = store
        messageStyle = store.value(for: SettingKey.themeStyle)
        showsSignatures = store.value(for: SettingKey.displaySignatures)
        swipesPages = store.value(for: SettingKey.topicPageSwipe)
        replyButton = store.value(for: SettingKey.replyButtonBehavior)
    }
}

extension ReplyButtonBehavior {
    /// Picker label, as legacy (`AppReplyButtonBehavior.title`, `Common.swift:243-263` @ 21173e7).
    var title: String {
        switch self {
        case .quick: "Réponse rapide"
        case .forum: "Répondre comme le forum"
        case .hidden: "Pas d'icône"
        }
    }
}

extension ThemeStyle {
    /// Picker label, as legacy (`themeStyleOptions`).
    var title: String {
        switch self {
        case .classic: "Classique"
        case .modern: "Moderne"
        }
    }
}
