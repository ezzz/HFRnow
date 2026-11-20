import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (icon Picker, lines 411-416, `applyIconSelection` 221-231) @ 87fe0d1c. Differences:
// a screen behind the "Icône" row (LOT-119 shell) instead of an inline picker; the checked icon follows the system's current icon;
// a grid by pack with a preview of every icon (GAP-148, LOT-189).
/// The "Icône" settings screen (LOT-123, packs and previews LOT-189).
struct AppIconSettingsView: View {
    @State private var model: AppIconSettingsModel

    /// Reads the choice from `store`.
    init(store: any SettingsStore, switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher()) {
        _model = State(initialValue: AppIconSettingsModel(store: store, switcher: switcher))
    }

    private let columns = [
        GridItem(.adaptive(minimum: AppIconGridLayout.minimumCell, maximum: AppIconGridLayout.maximumCell),
                 spacing: AppIconGridLayout.columnSpacing, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.pack.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: AppIconGridLayout.columnSpacing) {
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
            .padding(.horizontal, AppIconGridLayout.sidePadding)
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

    private let side = AppIconGridLayout.iconSide

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

/// The picker grid's metrics (operator 2026-11-16: thumbnails at the Home Screen size, 4 per row on a 6.1" iPhone).
enum AppIconGridLayout {
    /// The preview's side: the Home Screen icon size.
    static let iconSide: CGFloat = 60
    /// The thumbnail with its 4 pt padding (the selection ring) plus nothing else: `iconSide + 8`.
    static let minimumCell: CGFloat = 68
    static let maximumCell: CGFloat = 84
    static let columnSpacing: CGFloat = 12
    /// The screen's side padding (`AppIconSettingsView`).
    static let sidePadding: CGFloat = 16

    /// How many columns SwiftUI's adaptive grid fits in a content `width`.
    static func columnCount(contentWidth width: CGFloat) -> Int {
        max(1, Int(((width + columnSpacing) / (minimumCell + columnSpacing)).rounded(.down)))
    }

    /// The columns for a screen of `screenWidth` points.
    static func columnCount(screenWidth: CGFloat) -> Int {
        columnCount(contentWidth: screenWidth - 2 * sidePadding)
    }
}
