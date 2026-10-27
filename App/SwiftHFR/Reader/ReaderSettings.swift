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

    /// The image mode: the stored `display_images` value when there is one, else the reader's default (Wi-Fi only).
    /// `SettingKey.displayImages` defaults to `always` (legacy forced it); policy C (LOT-071) does not, so an absent key
    /// is read here, not through the setting's default.
    static func autoLoad(store: any SettingsStore) -> ImageAutoLoad {
        guard store.rawValue(forKey: SettingKey.displayImages.key) != nil else { return ImageAutoLoad(setting: nil) }
        return ImageAutoLoad(setting: store.value(for: SettingKey.displayImages))
    }
}
