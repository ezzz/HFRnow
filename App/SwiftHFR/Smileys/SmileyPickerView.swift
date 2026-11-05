import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (CombinedSmileyPickerView, FavoriteSmileyDetailView) @ 2440d79. Differences: see the
// doc comment and docs/lots/LOT-104-smiley-picker.md (GAP-087).
/// The smiley panel of the reply sheet (legacy `CombinedSmileyPickerView`, `HFRswift/Swift/AnswerView.swift:1051` @ 2440d79).
///
/// Differences: no forum-smiley section and no search (their own lots); section collapse states keep legacy's
/// `@AppStorage` keys; detail is a sheet instead of an overlay card (decision of the lot, same actions).
struct SmileyPickerView: View {
    @Bindable var model: SmileyPickerModel
    /// Called with the code to insert, right before the panel closes.
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("AnswerView.smileys.basic.expanded") private var basicExpanded = true
    @AppStorage("AnswerView.smileys.appFavorites.expanded") private var favoritesExpanded = true

    private let basicColumns = [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 4)]
    private let favoriteColumns = [GridItem(.adaptive(minimum: 78, maximum: 90), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    section("Smileys basiques", count: model.basic.count, expanded: $basicExpanded) {
                        if model.basic.isEmpty {
                            Text("Catalogue de smileys indisponible.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            grid(model.basic, columns: basicColumns, compact: true) { model.tap(basic: $0) }
                        }
                    }
                    section("Favoris de l’app", count: model.favorites.count, expanded: $favoritesExpanded) {
                        if model.favorites.isEmpty {
                            Text("Aucun favori dans l’app pour le moment.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            grid(model.favorites, columns: favoriteColumns, compact: false) { model.tap(favorite: $0) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .navigationTitle("Smileys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .overlay(alignment: .bottom) { noticeBanner }
        }
        .presentationDetents([.large])
        .sheet(item: $model.presented) { smiley in
            SmileyDetailView(model: model, smiley: smiley)
                .presentationDetents([.medium])
        }
        .task { await model.loadFavorites() }
        .task(id: model.notice) {
            guard let notice = model.notice else { return }
            AccessibilityNotification.Announcement(notice).post()
            try? await Task.sleep(for: .seconds(2.5))
            model.clearNotice()
        }
        .onChange(of: model.chosen) { _, chosen in
            guard let chosen else { return }
            onInsert(chosen.code)
            dismiss()
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
        }
    }

    private func section<Content: View>(
        _ title: String, count: Int, expanded: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded.wrappedValue ? "Développé" : "Réduit")
            if expanded.wrappedValue { content() }
        }
    }

    private func grid(
        _ smileys: [PickerSmiley], columns: [GridItem], compact: Bool, action: @escaping (PickerSmiley) -> Void
    ) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(smileys) { smiley in
                Button { action(smiley) } label: { SmileyCell(smiley: smiley, compact: compact) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(smiley.code)
            }
        }
    }
}

/// One grid cell (legacy `SmileyGridCell`, `AnswerView.swift:1634`).
private struct SmileyCell: View {
    let smiley: PickerSmiley
    let compact: Bool

    @State private var hasImage = false

    var body: some View {
        // The code shows until the image is there (offline, slow, refused): the tiles stay tellable apart.
        SmileyThumbnailView(url: smiley.imageURL, hasImage: $hasImage)
            .overlay { if !hasImage { Text(smiley.code).font(.caption2).foregroundStyle(.secondary).minimumScaleFactor(0.5).lineLimit(1) } }
            .frame(width: compact ? 40 : 70, height: compact ? 32 : 50)
            .frame(maxWidth: .infinity, minHeight: compact ? 40 : 58)
            .background(.quaternary, in: .rect(cornerRadius: compact ? 7 : 8))
            .contentShape(Rectangle())
    }
}

/// The detail of a favourite: preview, code, insert and remove (legacy `FavoriteSmileyDetailView`, `AnswerView.swift:1473`).
private struct SmileyDetailView: View {
    let model: SmileyPickerModel
    let smiley: PickerSmiley

    var body: some View {
        VStack(spacing: 16) {
            SmileyThumbnailView(url: smiley.imageURL, contentMode: .scaleAspectFit)
                .frame(height: 120)
                .accessibilityHidden(true)
            Text(smiley.code).font(.title3.monospaced()).textSelection(.enabled)
            Button("Insérer", systemImage: "text.insert") { model.insertPresented() }
                .buttonStyle(.borderedProminent)
            Button(model.isFavorite(smiley) ? "Retirer des favoris" : "Ajouter aux favoris",
                   systemImage: model.isFavorite(smiley) ? "star.slash" : "star") {
                Task { await model.setFavorite(smiley, !model.isFavorite(smiley)) }
            }
        }
        .padding()
    }
}
