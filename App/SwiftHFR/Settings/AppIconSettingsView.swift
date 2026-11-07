import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (icon Picker, lines 360-365, `applyIconSelection` 213-224) @ 2440d79. Differences:
// a screen behind the "Icône" row (LOT-119 shell) instead of an inline picker; no preview art (pending asset).
/// The "Icône" settings screen (LOT-123).
struct AppIconSettingsView: View {
    @State private var model: AppIconSettingsModel

    /// Reads the choice from `store`.
    init(store: any SettingsStore, switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher()) {
        _model = State(initialValue: AppIconSettingsModel(store: store, switcher: switcher))
    }

    var body: some View {
        Form {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        Task { await model.select(option) }
                    } label: {
                        HStack {
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if option == model.selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityAddTraits(option == model.selection ? .isSelected : [])
                }
            } footer: {
                if !model.isAvailable { Text("Les icônes alternatives ne sont pas disponibles sur cet appareil.") }
            }
            .disabled(!model.isAvailable || model.isSwitching)
        }
        .alert("Icône", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle("Icône")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Icône") {
    NavigationStack { AppIconSettingsView(store: InMemorySettingsStore()) }
}
