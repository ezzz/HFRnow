import HFRNetwork
import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (GiphyPanel :2294-2340, SDK picker with confirmation screen) @ 2440d79 (GAP-089).
// Differences: our own grid over the REST client (LOT-098); notice N1 before the first request (LOT-071); LOT-185 rules: the search
// bar is a `safeAreaBar` whose field is system glass (#856), no hand-made fill; the confirmation is pushed in the panel, not a
// third sheet (#1177).
/// The GIF panel of the reply sheet: trending or search results in a grid, a tap opens a confirmation, "Insérer" posts
/// `[img]<url>[/img]`. Thin: every rule is in `GifPickerModel`.
struct GifPickerView: View {
    @Bindable var model: GifPickerModel
    /// Called with the snippet to insert, right before the panel closes.
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isAskingNotice = false
    /// The GIF the confirmation shows, kept while it pops after « Retour » cleared the selection.
    @State private var confirmed: GiphyGIF?
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 6)]

    var body: some View {
        ThemedNavigationStack {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) { searchBar }
                .navigationTitle("GIF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetCloseToolbarItem { dismiss() }
                }
                .alert(AlertTitles.gifServiceQuestion, isPresented: $isAskingNotice) {
                    Button("Annuler", role: .cancel) { dismiss() }
                    Button("Continuer") { Task { await model.acceptNotice() } }
                } message: {
                    Text(model.noticeMessage)
                }
                // Pushed, not a third sheet over the composer (#1177; HIG › Sheets: one sheet at a time): back returns to
                // the grid.
                .navigationDestination(isPresented: isConfirming) {
                    if let gif = model.selected ?? confirmed {
                        GifConfirmationView(model: model, gif: gif) { snippet in
                            onInsert(snippet)
                            model.selected = nil
                            dismiss()
                        }
                        .appScreenBackground()
                    }
                }
                .onChange(of: model.selected?.id) { _, id in if id != nil { confirmed = model.selected } }
        }
        .presentationDetents([.large])
        .task {
            isAskingNotice = model.isAskingNotice
            await model.start()
        }
    }

    /// The confirmation is shown while a GIF is selected; going back clears the selection.
    private var isConfirming: Binding<Bool> {
        Binding(get: { model.selected != nil }, set: { if !$0 { model.selected = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            message("Les GIF viennent d'un service tiers.", icon: "g.circle", action: ("Afficher les GIF", { isAskingNotice = true }))
        case .loading:
            ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            message(reason, icon: "wifi.exclamationmark", action: ("Réessayer", { Task { await model.retry() } }))
        case .loaded where model.items.isEmpty:
            message("Aucun GIF trouvé. Essaie avec un autre mot.", icon: "questionmark.bubble", action: nil)
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.items) { gif in
                    Button { searchFocused = false; model.selected = gif } label: { cell(gif) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(gif.title.isEmpty ? "GIF" : gif.title)
                        .onAppear { Task { await model.loadMoreIfNeeded(after: gif) } }
                }
            }
            .padding(8)
            footer
        }
    }

    private func cell(_ gif: GiphyGIF) -> some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = model.previewURL(of: gif) {
                    SmileyThumbnailView(url: url, contentMode: .scaleAspectFill, source: .gif)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView().padding()
        } else if model.moreFailed {
            Button("Réessayer") { Task { await model.loadMore() } }.padding()
        }
    }

    private func message(_ text: String, icon: String, action: (title: String, run: () -> Void)?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action { Button(action.title, action: action.run) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var searchBar: some View {
        HStack(spacing: GifSearchClearButton.spacing) {
            TextField("Rechercher un GIF…", text: $model.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { searchFocused = false; Task { await model.submitSearch() } }
                .disabled(model.phase == .idle)
            if !model.query.isEmpty {
                GifSearchClearButton { model.query = ""; Task { await model.submitSearch() } }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        // System glass, not a hand-made fill: it keeps the field legible over any GIF, and the system swaps it for an opaque
        // surface under Reduce Transparency / Increase Contrast (#856; glass for floating elements, LOT-185).
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// The confirmation screen of the choice (legacy `showConfirmationScreen = true`, `AnswerView.swift:2307` @ 2440d79).
private struct GifConfirmationView: View {
    let model: GifPickerModel
    let gif: GiphyGIF
    let onInsert: (String) -> Void
    /// The full GIF is shown (it can take a moment, and a very large one stays a still frame: `SmileyImageLoader.maximumAnimationPixels`).
    @State private var hasOriginal = false

    /// The small rendition at once, the original over it as soon as it is decoded, a spinner meanwhile.
    private var preview: some View {
        ZStack {
            if let small = model.previewURL(of: gif) {
                SmileyThumbnailView(url: small, contentMode: .scaleAspectFit, source: .gif)
            }
            SmileyThumbnailView(url: gif.originalURL, contentMode: .scaleAspectFit, hasImage: $hasOriginal, source: .gif)
            if !hasOriginal { ProgressView() }
        }
    }

    /// Pushed inside the panel (#1177): the system back button goes back to the grid, so no « Annuler » of its own.
    var body: some View {
        VStack(spacing: 16) {
            preview
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel(gif.title.isEmpty ? "Aperçu du GIF" : gif.title)
            Button("Insérer") { if let snippet = model.snippet(for: gif) { onInsert(snippet) } }
                .appProminentButtonStyle()
                .disabled(model.snippet(for: gif) == nil)
        }
        .padding()
        .navigationTitle("Insérer ce GIF ?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var aspect: CGFloat {
        guard let width = gif.originalWidth, let height = gif.originalHeight, width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

extension View {
    /// Adds the GIF sheet to the composer (LOT-155), opened when `request` turns true (the "GIF Giphy" button of the control row,
    /// #653, shown only when `services.isAvailable`). The panel's model is built then, so nothing is read or requested before the
    /// member opens it. `onClosed` runs when the sheet closes after an insertion (the composer takes focus back).
    func gifPanel(
        services: GifServices, formatting: ComposerFormattingModel, request: Binding<Bool>, onClosed: @escaping () -> Void
    ) -> some View {
        modifier(GifPanel(services: services, formatting: formatting, request: request, onClosed: onClosed))
    }
}

/// The composer's GIF entry: the saved caret and the sheet.
private struct GifPanel: ViewModifier {
    let services: GifServices
    let formatting: ComposerFormattingModel
    @Binding var request: Bool
    let onClosed: () -> Void
    @State private var picker: GifPickerModel?
    /// A GIF was inserted by the open panel.
    @State private var inserted = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, requested in
                guard requested else { return }
                request = false
                guard services.isAvailable, picker == nil else { return }
                inserted = false
                formatting.beginPick()
                picker = GifPickerModel(services: services)
            }
            .sheet(item: $picker, onDismiss: { if inserted { onClosed() } }, content: { picker in
                GifPickerView(model: picker) { snippet in
                    formatting.insertPicked(snippet)
                    inserted = true
                }
            })
    }
}

/// The ✕ that clears the search field: a 44 pt hit region (#1296) that overflows the bar's layout, so the glyph and the text
/// field keep their place and width (same technique as `PollAnswerRemoveButton`, #1292). The region never reaches into the
/// text field: its leading overhang is capped at the stack's spacing and the rest goes to the trailing side, which has the
/// bar's and the screen's margins to spare.
struct GifSearchClearButton: View {
    /// The spacing between the field and the ✕ in the search bar, which caps how far the region reaches over the field.
    static let spacing: CGFloat = 8

    let action: () -> Void
    /// Test seams: the laid-out frames (global) of the hit region (the label's frame, before the negative padding) and of the
    /// visible glyph.
    var regionProbe: (@MainActor (CGRect) -> Void)?
    var glyphProbe: (@MainActor (CGRect) -> Void)?
    /// The glyph's size once laid out, which the overhang depends on (the default size until it is read).
    @State private var glyph = CGSize(width: 20, height: 20)

    var body: some View {
        let sideways = 2 * MinimumHitRegion.overhang(of: glyph.width)
        let leading = min(sideways / 2, Self.spacing)
        let vertical = MinimumHitRegion.overhang(of: glyph.height)
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                .onGeometryChange(for: CGSize.self, of: \.size) { glyph = $0 }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { glyphProbe?($0) })
                // The margins are the overhang, so the glyph sits where the negative padding below puts the layout back.
                .padding(.leading, leading).padding(.trailing, sideways - leading).padding(.vertical, vertical)
                .minimumHitRegion()
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { regionProbe?($0) })
        }
        .buttonStyle(.plain)
        .padding(.leading, -leading)
        .padding(.trailing, -(sideways - leading))
        .padding(.vertical, -vertical)
        .accessibilityLabel("Effacer")
    }
}
