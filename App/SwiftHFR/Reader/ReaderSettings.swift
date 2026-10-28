import Foundation
import HFRModels
import HFRStorage

/// The settings the reader reads, each time it needs them (no settings screen yet: FEAT-011 and the signature switch
/// come later; a value stored by them, or migrated from legacy, is honoured).
struct ReaderSettings: Sendable {
    /// Whether third-party images load without a tap right now.
    let autoLoadsThirdPartyImages: @Sendable () -> Bool
    /// Display choices for the next document.
    let renderOptions: @Sendable () -> ReaderRenderOptions

    /// Settings read from `store`, with `isOnWiFi` for the Wi-Fi only mode.
    static func live(store: any SettingsStore, isOnWiFi: @escaping @Sendable () -> Bool) -> ReaderSettings {
        ReaderSettings(
            autoLoadsThirdPartyImages: {
                autoLoad(store: store).loadsThirdPartyImages(onWiFi: isOnWiFi())
            },
            renderOptions: {
                ReaderRenderOptions(showsSignatures: store.value(for: SettingKey.displaySignatures))
            }
        )
    }

    /// The image mode from `display_images` (default `wifi`, policy C).
    static func autoLoad(store: any SettingsStore) -> ImageAutoLoad {
        ImageAutoLoad(setting: store.value(for: SettingKey.displayImages))
    }
}
