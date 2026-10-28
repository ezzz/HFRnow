import HFRModels
import HFRStorage
import SwiftUI

/// What a settings row leads to. Later lots add their cases here (theme: LOT-121, icon: LOT-123) and replace the
/// placeholder of their case, so the shell does not change again.
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
    @State private var general: GeneralSettingsModel

    /// Reads the settings from `store`; the live app re-applies the orientation when the rotation switch changes.
    init(store: any SettingsStore = UserDefaultsSettingsStore(), rotationChanged: @escaping @MainActor () -> Void = {}) {
        _general = State(initialValue: GeneralSettingsModel(store: store, rotationChanged: rotationChanged))
    }

    var body: some View {
        Form {
            Section("Général") {
                Picker("Écran de démarrage", selection: $general.startupScreen) {
                    ForEach(StartupScreen.allCases, id: \.self) { Text($0.title).tag($0) }
                }
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
                Toggle("Densité compacte", isOn: $general.compactMode)
                Toggle("Rotation de l’écran", isOn: $general.allowsRotation)
                Toggle(isOn: $general.opensLinksInDefaultBrowser) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Navigateur par défaut")
                        Text("Désactivé : navigateur intégré")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Apparence") {
                ForEach([SettingsDestination.theme, .icon], id: \.self) { destination in
                    NavigationLink(value: destination) { Label(destination.title, systemImage: destination.symbol) }
                }
            }
        }
        .listSectionSpacing(general.compactMode ? .custom(8) : .default)
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsDestination.self) { destination in
            ContentUnavailableView(
                destination.title, systemImage: destination.symbol,
                description: Text("Ce réglage arrive dans une prochaine version.")
            )
            .navigationTitle(destination.title)
        }
    }
}

#Preview("Réglages") {
    NavigationStack { SettingsView(store: InMemorySettingsStore()) }
}
