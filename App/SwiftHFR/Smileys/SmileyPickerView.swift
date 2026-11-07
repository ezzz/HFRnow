import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (CombinedSmileyPickerView, FavoriteSmileyDetailView) @ 2440d79. Differences: see the
// doc comment and the specs LOT-104 (GAP-087) and LOT-105 (GAP-088) in docs/lots/.
// LOT-185: the search bar is a `safeAreaBar` without fill and the notice capsule is glass; GAP row pending #545.
/// The smiley panel of the reply sheet (legacy `CombinedSmileyPickerView`, `HFRswift/Swift/AnswerView.swift:1051` @ 2440d79).
///
/// Differences: no forum-smiley section (its own lot); the search bar, history and keywords are LOT-105;
/// section collapse states keep legacy's `@AppStorage` keys; detail is a sheet instead of an overlay card (decision of the
/// lot, same actions).
struct SmileyPickerView: View {
    @Bindable var model: SmileyPickerModel
    /// Called with the code to insert, right before the panel closes.
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("AnswerView.smileys.basic.expanded") private var basicExpanded = true
    @AppStorage("AnswerView.smileys.appFavorites.expanded") private var favoritesExpanded = true
    @AppStorage("AnswerView.smileys.search.allKeywords") private var requireAll = false
    @FocusState private var searchFocused: Bool

    private let basicColumns = [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 4)]
    private let favoriteColumns = [GridItem(.adaptive(minimum: 78, maximum: 90), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let search = model.search, search.isSearching {
                    searchResults(search)
                } else {
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
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if let search = model.search { searchBar(search) }
            }
            .navigationTitle("Smileys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .overlay(alignment: .top) { noticeBanner }
        }
        .presentationDetents([.large])
        .sheet(item: $model.presented) { smiley in
            SmileyDetailView(model: model, smiley: smiley, requireAll: requireAll)
                .presentationDetents([.medium, .large])
        }
        .task { await model.loadFavorites() }
        .task { await model.search?.refreshSuggestions() }
        .onChange(of: model.search?.text) { Task { await model.search?.refreshSuggestions() } }
        .onDisappear { model.search?.stop() }
        .task(id: model.notice) {
            guard let notice = model.notice else { return }
            AccessibilityNotification.Announcement(notice).post()
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                // A newer notice replaced this one: its own timer clears it.
                return
            }
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
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
        }
    }

    // MARK: Search (LOT-105)

    @ViewBuilder
    private func searchResults(_ search: SmileySearchModel) -> some View {
        switch search.phase {
        case .results(let smileys):
            grid(smileys, columns: favoriteColumns, compact: false) { model.tap(result: $0) }.padding(8)
        case .loading:
            ProgressView("Recherche…").frame(maxWidth: .infinity).padding(.top, 80)
        case .empty:
            searchMessage("Aucun smiley trouvé", detail: "Essayez avec un autre mot-clé.", icon: "questionmark.bubble", search: search)
        case .tooShort:
            searchMessage(
                "Recherche trop courte",
                detail: "Saisissez au moins \(SmileySearchModel.minimumLength) caractères pour lancer une recherche.",
                icon: "text.magnifyingglass", search: search
            )
        case .failed(let reason):
            searchMessage("Recherche impossible", detail: reason, icon: "wifi.exclamationmark", search: search)
        case .library:
            EmptyView()
        }
    }

    private func searchMessage(_ title: String, detail: String, icon: String, search: SmileySearchModel) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retour aux smileys") { search.clear() }.font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 70)
    }

    private func searchBar(_ search: SmileySearchModel) -> some View {
        @Bindable var search = search
        return VStack(spacing: 8) {
            if !search.suggestions.isEmpty, !search.isSearching { suggestionChips(search) }
            HStack(spacing: 8) {
                if search.isSearching {
                    Button { searchFocused = false; search.clear() } label: { Image(systemName: "chevron.left").padding(8) }
                        .accessibilityLabel("Retour aux smileys")
                }
                HStack {
                    TextField("Rechercher un smiley…", text: $search.text)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { startSearch(search) }
                    if !search.text.isEmpty {
                        Button { search.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Effacer")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                Button { startSearch(search) } label: { Image(systemName: "magnifyingglass").padding(8) }
                    .disabled(!search.canSearch)
                    .accessibilityLabel("Rechercher")
            }
            if let hint = search.tooShortHint {
                Text(hint).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Tous les mots clés", isOn: $requireAll).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func startSearch(_ search: SmileySearchModel) {
        searchFocused = false
        search.submit(requireAll: requireAll)
    }

    private func suggestionChips(_ search: SmileySearchModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(search.suggestions, id: \.text) { entry in
                    Button {
                        searchFocused = false
                        search.submit(entry.text, requireAll: requireAll)
                    } label: {
                        Label(entry.text, systemImage: search.text.isEmpty ? "clock" : "magnifyingglass")
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
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

/// The detail of a smiley (favourite or search result): preview, code, insert, add or remove, and the wiki keywords
/// (legacy `FavoriteSmileyDetailView`, `AnswerView.swift:1473`).
private struct SmileyDetailView: View {
    let model: SmileyPickerModel
    let smiley: PickerSmiley
    let requireAll: Bool

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
            if let search = model.search { keywords(search) }
        }
        .padding()
        .task(id: smiley.code) { await model.search?.loadKeywords(for: smiley.code) }
        .onDisappear { model.search?.resetKeywords() }
    }

    @ViewBuilder
    private func keywords(_ search: SmileySearchModel) -> some View {
        switch search.keywords {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Chargement des mots clés…").font(.footnote)
        case .failed(let reason):
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        case .loaded(let words) where words.isEmpty:
            EmptyView()
        case .loaded(let words):
            VStack(alignment: .leading, spacing: 8) {
                Text("Mots clés").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(words, id: \.self) { word in
                            Button(word) { model.searchKeyword(word, requireAll: requireAll) }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
