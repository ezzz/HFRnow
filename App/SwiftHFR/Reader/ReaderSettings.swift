import Foundation
import HFRModels
import HFRStorage

/// The settings the reader reads, each time it needs them (the "Sujets" section of the settings screen writes them, LOT-106;
/// a value migrated from legacy is honoured as stored).
struct ReaderSettings: Sendable {
    /// Whether third-party images load without a tap right now.
    let autoLoadsThirdPartyImages: @Sendable () -> Bool
    /// Display choices for the next document.
    let renderOptions: @Sendable () -> ReaderRenderOptions
    /// Whether a horizontal swipe changes the page (`topic_page_swipe_navigation`, default on).
    let swipesPages: @Sendable () -> Bool

    /// Settings read from `store`, with `isOnWiFi` for the Wi-Fi only mode.
    static func live(store: any SettingsStore, isOnWiFi: @escaping @Sendable () -> Bool) -> ReaderSettings {
        ReaderSettings(
            autoLoadsThirdPartyImages: {
                autoLoad(store: store).loadsThirdPartyImages(onWiFi: isOnWiFi())
            },
            renderOptions: {
                ReaderRenderOptions(
                    showsSignatures: store.value(for: SettingKey.displaySignatures),
                    style: store.value(for: SettingKey.themeStyle)
                )
            },
            swipesPages: { store.value(for: SettingKey.topicPageSwipe) }
        )
    }

    /// The image mode from `display_images` (default `wifi`, policy C).
    static func autoLoad(store: any SettingsStore) -> ImageAutoLoad {
        ImageAutoLoad(setting: store.value(for: SettingKey.displayImages))
    }
}
