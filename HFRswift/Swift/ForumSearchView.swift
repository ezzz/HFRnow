//
//  ForumSearchView.swift
//  SuperHFRplus
//
//  Native SwiftUI UI for the global forum search.
//

import Combine
import SwiftUI

@MainActor
final class ForumSearchViewModel: ObservableObject {
    @Published var params: ForumSearchParams
    @Published var topics: [Topic] = []
    @Published var pageInfo: ForumSearchPageInfo = .empty
    @Published var isLoading = false
    @Published var hasSearched = false
    @Published var errorMessage: String?

    private let service: any ForumSearchServicing
    private var requestID = 0

    init(
        initialCategoryID: String = "13",
        service: (any ForumSearchServicing)? = nil
    ) {
        self.params = ForumSearchParams(
            searchText: "",
            categoryID: initialCategoryID.isEmpty ? "13" : initialCategoryID,
            searchType: .allWords,
            searchScope: .titleAndContent,
            dateRange: .fromBeginning
        )
        self.service = service ?? ObjCForumSearchService()
    }

    var resultSummary: String {
        guard hasSearched else { return "" }
        if topics.isEmpty {
            return "Aucun résultat"
        }
        let countText = topics.count == 1 ? "1 résultat" : "\(topics.count) résultats"
        return "\(countText) - p.\(max(pageInfo.pageNumber, 1))"
    }

    func search() async {
        await perform(requiresQuery: true) {
            await service.search(params: params)
        }
    }

    func fetchPage(urlString: String?) async {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        await perform(requiresQuery: false) {
            await service.fetchPage(urlString: urlString)
        }
    }

    func cancel() {
        requestID += 1
        service.cancel()
        isLoading = false
    }

    private func perform(
        requiresQuery: Bool,
        _ operation: () async -> Result<ForumSearchResult, ForumSearchError>
    ) async {
        let trimmedSearch = params.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requiresQuery || !trimmedSearch.isEmpty else {
            hasSearched = true
            errorMessage = ForumSearchError.emptyQuery.localizedDescription
            return
        }

        requestID += 1
        let currentRequestID = requestID
        hasSearched = true
        isLoading = true
        errorMessage = nil

        let result = await operation()
        guard currentRequestID == requestID else { return }

        isLoading = false
        switch result {
        case .success(let searchResult):
            topics = searchResult.topics
            pageInfo = searchResult.pageInfo
            AppHaptics.impact(.light)
        case .failure(.cancelled):
            break
        case .failure(let error):
            topics = []
            pageInfo = .empty
            errorMessage = error.localizedDescription
        }
    }
}

struct ForumSearchView: View {
    @StateObject private var viewModel: ForumSearchViewModel
    @AppStorage("recherche_categorie") private var storedCategoryID = "13"
    @State private var categories: [ForumSearchCategory]
    @State private var visitedURLs: Set<String> = []
    @FocusState private var searchFieldFocused: Bool

    init(viewModel: ForumSearchViewModel? = nil) {
        let initialCategoryID = UserDefaults.standard.string(forKey: "recherche_categorie") ?? "13"
        _viewModel = StateObject(wrappedValue: viewModel ?? ForumSearchViewModel(initialCategoryID: initialCategoryID))
        _categories = State(initialValue: ForumSearchCategory.loadCachedCategories(selectedCategoryID: initialCategoryID))
    }

    private var canSubmit: Bool {
        viewModel.params.isSubmittable && !viewModel.isLoading
    }

    private var shouldShowPagination: Bool {
        viewModel.hasSearched
        && !viewModel.topics.isEmpty
        && max(viewModel.pageInfo.lastPageNumber, 1) > 1
    }

    var body: some View {
        List {
            searchFormSection
            resultSection
        }
        .navigationTitle("Recherche")
        .safeAreaInset(edge: .bottom) {
            bottomAccessory
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    Button("Annuler") {
                        viewModel.cancel()
                    }
                } else {
                    Button {
                        startSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(!canSubmit)
                    .accessibilityLabel("Lancer la recherche")
                }
            }
        }
        .onAppear {
            if !categories.contains(where: { $0.id == viewModel.params.categoryID }) {
                categories = ForumSearchCategory.loadCachedCategories(selectedCategoryID: viewModel.params.categoryID)
            }
        }
        .onChange(of: viewModel.params.categoryID) { _, newValue in
            storedCategoryID = newValue
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var searchFormSection: some View {
        Section {
            TextField("Rechercher", text: $viewModel.params.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .onSubmit {
                    startSearch()
                }

            Picker("Catégorie", selection: $viewModel.params.categoryID) {
                ForEach(categories) { category in
                    Text(category.title).tag(category.id)
                }
            }

            Picker("Type", selection: $viewModel.params.searchType) {
                ForEach(ForumSearchParams.SearchType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Picker("Dans", selection: $viewModel.params.searchScope) {
                ForEach(ForumSearchParams.SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Picker("Période", selection: $viewModel.params.dateRange) {
                ForEach(ForumSearchParams.DateRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Button {
                startSearch()
            } label: {
                Label("Rechercher", systemImage: "magnifyingglass")
            }
            .disabled(!canSubmit)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.hasSearched || viewModel.isLoading {
            Section {
                if viewModel.isLoading && viewModel.topics.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recherche en cours")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if !viewModel.isLoading && viewModel.topics.isEmpty {
                    Text("Aucun résultat")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.topics) { topic in
                    ForumSearchTopicRow(
                        topic: topic,
                        isVisited: topic.isViewed || visitedURLs.contains(topic.aURL ?? ""),
                        onOpen: { openedURL in
                            if let openedURL, !openedURL.isEmpty {
                                visitedURLs.insert(openedURL)
                            }
                            topic.isLocallyViewedInApp = true
                            topic.isViewed = true
                        }
                    )
                }
            } header: {
                if !viewModel.resultSummary.isEmpty {
                    Text(viewModel.resultSummary)
                }
            }
        }
    }

    @ViewBuilder
    private var bottomAccessory: some View {
        if viewModel.isLoading {
            ForumSearchStatusBanner(onCancel: viewModel.cancel)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if shouldShowPagination {
            ForumSearchPaginationBar(
                pageInfo: viewModel.pageInfo,
                onFirst: { loadPage(viewModel.pageInfo.firstPageURL) },
                onPrevious: { loadPage(viewModel.pageInfo.previousPageURL) },
                onNext: { loadPage(viewModel.pageInfo.nextPageURL) },
                onLast: { loadPage(viewModel.pageInfo.lastPageURL) }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func startSearch() {
        guard canSubmit else { return }
        searchFieldFocused = false
        Task {
            await viewModel.search()
        }
    }

    private func loadPage(_ urlString: String?) {
        Task {
            await viewModel.fetchPage(urlString: urlString)
        }
    }
}

private struct ForumSearchTopicRow: View {
    let topic: Topic
    let isVisited: Bool
    let onOpen: (String?) -> Void

    private var cleanedTitle: String? {
        let rawTitle = topic._aTitle ?? ""
        let snippet = cleanedSnippet ?? ""
        guard !rawTitle.isEmpty, !snippet.isEmpty else {
            return rawTitle.isEmpty ? nil : rawTitle
        }

        let cleaned = rawTitle
            .replacingOccurrences(of: snippet, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? rawTitle : cleaned
    }

    private var cleanedSnippet: String? {
        guard let content = topic.sLastSearchPostContent else { return nil }
        let collapsed = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private var footerLeft: String? {
        let author = topic.aAuthorOfLastPost ?? ""
        let date = topic.aDateOfLastPost ?? ""
        if author.isEmpty { return date.isEmpty ? nil : date }
        if date.isEmpty { return author }
        return "\(author) - \(date)"
    }

    private var footerRight: String? {
        let maxPage = max(Int(topic.maxTopicPage), 1)
        return maxPage > 1 ? "\(maxPage) pages" : "1 page"
    }

    var body: some View {
        TopicListRowView(
            topic: topic,
            isVisited: isVisited,
            titleFont: nil,
            titleBaseSize: 14,
            titleWeight: isVisited ? .regular : .semibold,
            titleOverride: cleanedTitle,
            leadingBottomText: footerLeft,
            trailingBottomText: footerRight,
            detailText: cleanedSnippet,
            openContext: .globalSearch,
            onOpen: onOpen
        )
    }
}

private struct ForumSearchStatusBanner: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Recherche en cours")
                .font(.footnote)
            Spacer(minLength: 8)
            Button("Annuler", action: onCancel)
                .font(.footnote.weight(.semibold))
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .hfrGlassButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hfrGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ForumSearchPaginationBar: View {
    let pageInfo: ForumSearchPageInfo
    let onFirst: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onLast: () -> Void

    private var pageNumber: Int {
        max(pageInfo.pageNumber, 1)
    }

    private var lastPageNumber: Int {
        max(pageInfo.lastPageNumber, 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFirst) {
                Image(systemName: "backward.end")
            }
            .disabled(pageNumber <= 1 || pageInfo.firstPageURL == nil)

            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .disabled(pageNumber <= 1 || pageInfo.previousPageURL == nil)

            Spacer(minLength: 8)

            Text("\(pageNumber) / \(lastPageNumber)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(pageNumber >= lastPageNumber || pageInfo.nextPageURL == nil)

            Button(action: onLast) {
                Image(systemName: "forward.end")
            }
            .disabled(pageNumber >= lastPageNumber || pageInfo.lastPageURL == nil)
        }
        .hfrGlassButton()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .hfrGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ForumSearchCategory: Identifiable, Hashable {
    let id: String
    let title: String

    static func loadCachedCategories(selectedCategoryID: String) -> [ForumSearchCategory] {
        var categories = cachedCategories()
        if categories.isEmpty {
            categories = [ForumSearchCategory(id: "13", title: "Discussions")]
        }
        if !selectedCategoryID.isEmpty,
           !categories.contains(where: { $0.id == selectedCategoryID }) {
            categories.insert(ForumSearchCategory(id: selectedCategoryID, title: "Catégorie \(selectedCategoryID)"), at: 0)
        }
        return categories
    }

    private static func cachedCategories() -> [ForumSearchCategory] {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last else {
            return []
        }
        let url = directory.appendingPathComponent("forumsCache.plist")
        guard let data = try? Data(contentsOf: url),
              let forums = NSKeyedUnarchiver.unarchiveObject(with: data) as? [Forum] else {
            return []
        }

        return forums.compactMap { forum in
            let id = "\(forum.getHFRID())"
            guard id != "0" else { return nil }
            return ForumSearchCategory(id: id, title: forum.aTitle ?? "Catégorie \(id)")
        }
    }
}
