import HFRNetwork
import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (GiphyPanel :2294-2340, SDK picker with confirmation screen) @ 2440d79 (GAP-089).
// Differences: our own grid over the REST client (LOT-098); notice N1 before the first request (LOT-071); LOT-185 rules: the search
// bar is a `safeAreaBar` without fill, no hand-made glass.
/// The GIF panel of the reply sheet: trending or search results in a grid, a tap opens a confirmation, "Insérer" posts
/// `[img]<url>[/img]`. Thin: every rule is in `GifPickerModel`.
struct GifPickerView: View {
    @Bindable var model: GifPickerModel
    /// Called with the snippet to insert, right before the panel closes.
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isAskingNotice = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 6)]

    var body: some View {
        ThemedNavigationStack {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) { searchBar }
                .navigationTitle("GIF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                }
                .alert("Service de GIF", isPresented: $isAskingNotice) {
                    Button("Annuler", role: .cancel) { dismiss() }
                    Button("Continuer") { Task { await model.acceptNotice() } }
                } message: {
                    Text(model.noticeMessage)
                }
        }
        .presentationDetents([.large])
        .sheet(item: $model.selected) { gif in
            GifConfirmationView(model: model, gif: gif) { snippet in
                onInsert(snippet)
                model.selected = nil
                dismiss()
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            isAskingNotice = model.isAskingNotice
            await model.start()
        }
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
            message("Aucun GIF trouvé. Essayez avec un autre mot.", icon: "questionmark.bubble", action: nil)
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
        HStack {
            TextField("Rechercher un GIF…", text: $model.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { searchFocused = false; Task { await model.submitSearch() } }
                .disabled(model.phase == .idle)
            if !model.query.isEmpty {
                Button { model.query = ""; Task { await model.submitSearch() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// The confirmation screen of the choice (legacy `showConfirmationScreen = true`, `AnswerView.swift:2307` @ 2440d79).
private struct GifConfirmationView: View {
    let model: GifPickerModel
    let gif: GiphyGIF
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        ThemedNavigationStack {
            VStack(spacing: 16) {
                preview
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel(gif.title.isEmpty ? "Aperçu du GIF" : gif.title)
                Button("Insérer") { if let snippet = model.snippet(for: gif) { onInsert(snippet) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.snippet(for: gif) == nil)
            }
            .padding()
            .navigationTitle("Insérer ce GIF ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
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
    /// The caret when "GIF" was tapped: the sheet takes focus, so the live selection is not trusted (as for images and smileys).
    @State private var caret = NSRange(location: 0, length: 0)

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, requested in
                guard requested else { return }
                request = false
                guard services.isAvailable, picker == nil else { return }
                inserted = false
                caret = formatting.selectedRange
                picker = GifPickerModel(services: services)
            }
            .sheet(item: $picker, onDismiss: { if inserted { onClosed() } }, content: { picker in
                GifPickerView(model: picker) { snippet in
                    formatting.selectedRange = caret
                    formatting.insert(snippet)
                    inserted = true
                }
            })
    }
}
