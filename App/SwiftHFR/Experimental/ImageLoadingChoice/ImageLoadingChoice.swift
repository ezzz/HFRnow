import HFRModels
import HFRStorage
import SwiftUI

// New in SwiftHFR (#902, operator 2026-11-14): legacy forces `display_images = "yes"` at every launch with no setting
// (`Classes/HFRplusAppDelegate.m:117-118` at 87fe0d1c). The choice below is the experimental addition; off, images always load.
/// When third-party images load (`display_images`, FEAT-011, policy C point 2), behind Réglages › Expérimental › « Chargement
/// des images » (#902).
enum ImageLoadingChoice {
    // EXPERIMENTAL(imageLoadingChoice, #902): replaces the always-load default of the reader.
    /// The image mode: the stored `display_images` while the option is on (« Toujours » until the user picks another), always
    /// otherwise, whatever an earlier build stored. The reader reads this on every page and image request.
    static func autoLoad(store: any SettingsStore) -> ImageAutoLoad {
        guard store.value(for: SettingKey.experimentalImageLoadingChoice) else { return .always }
        return ImageAutoLoad(setting: store.value(for: SettingKey.displayImages))
    }
}

extension ImageDisplayMode {
    /// Picker label. "Jamais" keeps images behind a tap (the reader's placeholder), it never fetches them by itself.
    var title: String {
        switch self {
        case .always: "Toujours"
        case .wifiOnly: "Wi-Fi uniquement"
        case .never: "Jamais (au toucher)"
        }
    }
}

/// The Toujours / Wi-Fi uniquement / Jamais picker, written to `display_images` as soon as it changes.
struct ImageLoadingChoicePicker: View {
    let store: any SettingsStore
    @State private var mode: ImageDisplayMode

    init(store: any SettingsStore) {
        self.store = store
        _mode = State(initialValue: store.value(for: SettingKey.displayImages))
    }

    var body: some View {
        Picker("Charger les images", selection: $mode) {
            ForEach(ImageDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .onChange(of: mode) { _, new in store.set(new, for: SettingKey.displayImages) }
    }
}
