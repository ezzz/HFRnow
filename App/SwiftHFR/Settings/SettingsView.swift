import HFRModels
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView) @ 2440d79. Differences: each section comes with its lot; only "Général"
// for now.
/// What a settings row leads to. Later lots add their cases here (theme: LOT-121, icon: LOT-123) and replace their
/// case's placeholder in `SettingsDestinationView`, so the shell does not change again.
enum SettingsDestination: Hashable {
    case theme
    case icon

    /// Row label.
    var title: String {
        switch self {
        case .theme: "Thème"
        case .icon: "Icône"
        }
    }

    var symbol: String {
        switch self {
        case .theme: "paintpalette"
        case .icon: "app.dashed"
        }
    }
}

/// The settings screen (LOT-119): the "Général" section and the entry points of the sections other lots fill in.
struct SettingsView: View {
    /// The app's one settings model: a change here re-renders every screen at once (LOT-169).
    @Environment(GeneralSettingsModel.self) private var general

    var body: some View {
        @Bindable var general = general
        Form {
            Section("Général") {
                Picker("Écran de démarrage", selection: $general.startupScreen) {
                    ForEach(StartupScreen.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Mode compact", isOn: $general.compactMode)
                Toggle("Réduire la tab bar au scroll", isOn: $general.minimizesTabBarOnScroll)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Taille du texte", value: "\(general.textSizePercent) %")
                    Slider(
                        value: Binding(
                            get: { Double(general.textSizePercent) },
                            set: { general.textSizePercent = Int($0.rounded()) }
                        ),
                        in: Double(SettingKey.textSizePercentRange.lowerBound)...Double(SettingKey.textSizePercentRange.upperBound),
                        step: Double(SettingKey.textSizePercentStep)
                    )
                    .accessibilityLabel("Taille du texte")
                    .accessibilityValue("\(general.textSizePercent) %")
                }
                Toggle("Rotation d’écran", isOn: $general.allowsRotation)
                Toggle(isOn: $general.opensLinksInDefaultBrowser) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Navigateur par défaut")
                        Text("Désactivé : navigateur intégré")
                            .scaledFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink { SettingsDestinationView(destination: .icon) } label: {
                    Text(SettingsDestination.icon.title)
                }
            }
            Section("Thème") {
                NavigationLink { SettingsDestinationView(destination: .theme) } label: {
                    Text(SettingsDestination.theme.title)
                }
            }
        }
        // Legacy settings spacing in compact mode (`AppSettingsView.swift:597` at 21173e77).
        .listSectionSpacing(general.compactMode ? .custom(8) : .default)
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The screen behind a settings row. Rows link to it directly, not by value: on iPhone the settings screen is presented by
/// the Plus stack's `navigationDestination(item:)`, and a value pushed from such a screen never resolves.
struct SettingsDestinationView: View {
    let destination: SettingsDestination

    var body: some View {
        switch destination {
        case .theme:
            ThemeSettingsView()
        case .icon:
            ContentUnavailableView(
                destination.title, systemImage: destination.symbol,
                description: Text("Ce réglage arrive dans une prochaine version.")
            )
            .navigationTitle(destination.title)
        }
    }
}

#Preview("Réglages") {
    NavigationStack { SettingsView() }
        .environment(GeneralSettingsModel(store: InMemorySettingsStore()))
        .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
}
