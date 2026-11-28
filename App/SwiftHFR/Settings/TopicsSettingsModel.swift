import HFRModels
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift ("Sujets" section, GAP-052/054/071: `theme_style`, `display_sig`;
// `topic_page_swipe_navigation` from `master` @21173e7:479) @ 2440d79. Differences: the swipe key is newer than 2440d79;
// "Masquer les pseudos blacklistés" (`blacklist_hide_pseudo`, LOT-118); the "Bouton +" row is LOT-086's; the smiley size stays dropped
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
    /// « Vidéos » (`embedded_videos`): the player on a tap (« Intégrée », the default: legacy's `yes`, and its `both`) or the plain
    /// link (« Lien »: `no`). The reader asks for a video placeholder unless this is `.never` (#691).
    var videosMode: EmbeddedVideosMode {
        didSet { if videosMode != oldValue { store.set(videosMode, for: SettingKey.embeddedVideos) } }
    }
    /// The picker's two choices over `videosMode`: choosing « Intégrée » again keeps a legacy `both`.
    var embedsVideos: Bool {
        get { videosMode != .never }
        set { if newValue != embedsVideos { videosMode = newValue ? .inlinePlayer : .never } }
    }
    /// A horizontal swipe changes the reader's page (`topic_page_swipe_navigation`).
    var swipesPages: Bool {
        didSet { if swipesPages != oldValue { store.set(swipesPages, for: SettingKey.topicPageSwipe) } }
    }

    /// Collapse blocklisted posts to nothing instead of a tappable stub (`blacklist_hide_pseudo`, LOT-118).
    var hidesBlocklisted: Bool {
        didSet { if hidesBlocklisted != oldValue { store.set(hidesBlocklisted, for: SettingKey.hideBlocklistedPosts) } }
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
        videosMode = store.value(for: SettingKey.embeddedVideos)
        swipesPages = store.value(for: SettingKey.topicPageSwipe)
        replyButton = store.value(for: SettingKey.replyButtonBehavior)
        hidesBlocklisted = store.value(for: SettingKey.hideBlocklistedPosts)
    }
}

extension ReplyButtonBehavior {
    /// Picker label, as legacy (`AppReplyButtonBehavior.title`, `Common.swift:243-263` @ 21173e7).
    var title: String {
        switch self {
        case .quick: "Réponse rapide"
        case .forum: "Répondre comme le forum"
        case .hidden: "Pas d’icône"
        }
    }

    /// Whether this is the choice a fresh install gets (« Répondre comme le forum » since #1016): marked in the info bubble.
    var isDefault: Bool { self == SettingKey.replyButtonBehavior.defaultValue }

    /// One sentence for the info bubble of the « Bouton + » row (#1062, operator decision of 2026-11-17). It follows what the
    /// code does: `quick` and `forum` call the same `requestReply()` (LOT-086, GAP-083), so only the icon differs, and
    /// `hidden` leaves the quote entries of the message menu.
    var explanation: String {
        switch self {
        case .quick: "Icône « + » : ouvre ton brouillon du sujet, avec les citations sélectionnées ajoutées."
        case .forum:
            "Icône crayon : même réponse que « Réponse rapide » (ton brouillon du sujet, avec les citations sélectionnées), "
                + "seule l’icône change."
        case .hidden: "Pas de bouton de réponse : « Répondre » est dans le menu « … » du sujet, « Citer » dans le menu d’un message."
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
