import Foundation
import HFRModels
import HFRStorage

/// The settings the reader reads, each time it needs them (the image mode is set in Réglages by
/// `GeneralSettingsModel.imageLoading`, LOT-107; the layout, signatures and swipe by `TopicsSettingsModel`, LOT-106; a value
/// stored there, or migrated from legacy, is honoured).
struct ReaderSettings: Sendable {
    /// Whether third-party images load without a tap right now.
    let autoLoadsThirdPartyImages: @Sendable () -> Bool
    /// Display choices for the next document.
    let renderOptions: @Sendable () -> ReaderRenderOptions
    /// Whether a horizontal swipe changes the page (`topic_page_swipe_navigation`, default on).
    let swipesPages: @Sendable () -> Bool
    /// "Navigateur par défaut" (LOT-119): web links open in the system browser rather than in Safari's view in the app.
    var opensLinksInDefaultBrowser: @Sendable () -> Bool = { false }

    /// Settings read from `store`, with `isOnWiFi` for the Wi-Fi only mode. `pseudo` is the current account's (nil logged out),
    /// `pseudoLists` the lists the visibility policy reads each time a document is built (LOT-117; LOT-118 owns the lists).
    static func live(
        store: any SettingsStore, isOnWiFi: @escaping @Sendable () -> Bool, pseudo: String? = nil,
        pseudoLists: @escaping @Sendable () -> PseudoLists = { PseudoLists() }
    ) -> ReaderSettings {
        ReaderSettings(
            autoLoadsThirdPartyImages: {
                autoLoad(store: store).loadsThirdPartyImages(onWiFi: isOnWiFi())
            },
            renderOptions: {
                ReaderRenderOptions(
                    showsSignatures: store.value(for: SettingKey.displaySignatures),
                    style: store.value(for: SettingKey.themeStyle),
                    visibility: visibility(store: store, pseudo: pseudo, lists: pseudoLists())
                )
            },
            swipesPages: { store.value(for: SettingKey.topicPageSwipe) },
            opensLinksInDefaultBrowser: { store.value(for: SettingKey.opensLinksInDefaultBrowser) }
        )
    }

    /// The visibility policy of the account `pseudo`: its lists and the "Masquer les pseudos blacklistés" setting.
    static func visibility(store: any SettingsStore, pseudo: String?, lists: PseudoLists) -> VisibilityPolicy {
        VisibilityPolicy(
            ownPseudo: pseudo, blocklist: lists.blocklist, allowlist: lists.allowlist,
            hidesBlockedPseudo: store.value(for: SettingKey.hideBlocklistedPosts)
        )
    }

    /// The image mode from `display_images` (default `wifi`, policy C).
    static func autoLoad(store: any SettingsStore) -> ImageAutoLoad {
        ImageAutoLoad(setting: store.value(for: SettingKey.displayImages))
    }
}
