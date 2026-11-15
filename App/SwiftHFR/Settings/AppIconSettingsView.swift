import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (icon Picker, lines 360-365, `applyIconSelection` 213-224) @ 87fe0d1c. Differences:
// a screen behind the "Icône" row (LOT-119 shell) instead of an inline picker; the checked icon follows the system's current icon;
// a grid by pack with a preview of every icon (GAP-148, LOT-189).
/// The "Icône" settings screen (LOT-123, packs and previews LOT-189).
struct AppIconSettingsView: View {
    @State private var model: AppIconSettingsModel

    /// Reads the choice from `store`.
    init(store: any SettingsStore, switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher()) {
        _model = State(initialValue: AppIconSettingsModel(store: store, switcher: switcher))
    }

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.pack.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(section.options) { option in
                                AppIconCell(option: option, isSelected: option == model.selection) {
                                    Task { await model.select(option) }
                                }
                            }
                        }
                    }
                }
                if !model.isAvailable {
                    Text("Les icônes alternatives ne sont pas disponibles sur cet appareil.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .disabled(!model.isAvailable || model.isSwitching)
        }
        .background(Color(.systemGroupedBackground))
        .alert("Icône", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle("Icône")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One icon of the grid: its preview as on the Home Screen (light or dark with the appearance), its name, a ring when chosen.
private struct AppIconCell: View {
    let option: AppIconOption
    let isSelected: Bool
    let action: () -> Void

    private let side: CGFloat = 76

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(option.previewImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .padding(4)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: side * 0.2237 + 4, style: .continuous).strokeBorder(.tint, lineWidth: 3)
                        }
                    }
                Text(option.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Icône") {
    NavigationStack { AppIconSettingsView(store: InMemorySettingsStore()) }
}
