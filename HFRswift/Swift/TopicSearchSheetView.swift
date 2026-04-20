//
//  TopicSearchSheetView.swift
//  SuperHFRplus
//
//  Bottom sheet that captures the intra-topic search criteria.
//  Submission posts to /transsearch.php via TopicSearchServicing and
//  returns the redirect URL + refined params to the caller.
//

import SwiftUI

struct TopicSearchSheetView: View {
    /// Initial values (prefilled from the current page's parsed form, or .empty).
    let initialParams: TopicSearchParams
    /// If true, we are already on a results page — the "Depuis le début" toggle starts OFF
    /// so that tapping "Rechercher" continues the pagination of the current query.
    let isFromResultsPage: Bool
    let searchService: any TopicSearchServicing
    let onResultReady: (URL, TopicSearchParams) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var word: String
    @State private var spseudo: String
    @State private var filterEnabled: Bool
    @State private var fromFirstPost: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        initialParams: TopicSearchParams,
        isFromResultsPage: Bool,
        searchService: any TopicSearchServicing = ObjCTopicSearchService(),
        onResultReady: @escaping (URL, TopicSearchParams) -> Void
    ) {
        self.initialParams = initialParams
        self.isFromResultsPage = isFromResultsPage
        self.searchService = searchService
        self.onResultReady = onResultReady
        _word = State(initialValue: initialParams.word)
        _spseudo = State(initialValue: initialParams.spseudo)
        _filterEnabled = State(initialValue: initialParams.filterEnabled)
        // When re-opening from a results page, keep the existing pagination (fromFirstPost = false).
        // Fresh search from a regular topic page defaults to "depuis le début" = true.
        _fromFirstPost = State(
            initialValue: isFromResultsPage ? initialParams.fromFirstPost : true
        )
    }

    private enum Field: Hashable {
        case word
        case spseudo
    }

    private var canSubmit: Bool {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPseudo = spseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSubmitting && (!trimmedWord.isEmpty || !trimmedPseudo.isEmpty)
    }

    private func currentParams() -> TopicSearchParams {
        var params = initialParams
        params.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        params.spseudo = spseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        params.filterEnabled = filterEnabled
        params.fromFirstPost = fromFirstPost
        return params
    }

    private func submit() {
        guard canSubmit else { return }
        let params = currentParams()
        isSubmitting = true
        errorMessage = nil
        focusedField = nil

        Task { @MainActor in
            let result = await searchService.performSearch(params: params)
            isSubmitting = false
            switch result {
            case .success(let url):
                onResultReady(url, params)
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Mot-clé", text: $word)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .word)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .spseudo }
                        if !word.isEmpty {
                            Button {
                                word = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Effacer")
                        }
                    }

                    HStack {
                        TextField("Pseudo", text: $spseudo)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .spseudo)
                            .submitLabel(.search)
                            .onSubmit { submit() }
                        if !spseudo.isEmpty {
                            Button {
                                spseudo = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Effacer")
                        }
                    }
                } footer: {
                    Text("Renseigne un mot-clé, un pseudo, ou les deux.")
                }

                Section {
                    Toggle(isOn: $filterEnabled) {
                        Label("Filtrer les messages", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Toggle(isOn: $fromFirstPost) {
                        Label("Depuis le début du sujet", systemImage: "arrow.up.to.line")
                    }
                } footer: {
                    Text(fromFirstPost
                         ? "La recherche repart du premier message du sujet."
                         : "La recherche continue depuis la position courante.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .disabled(isSubmitting)
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView("Recherche en cours…")
                            .padding(24)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isSubmitting)
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        Label("Rechercher", systemImage: "magnifyingglass")
                    }
                    .ifAvailableiOS26GlassProminentCompat()
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                focusedField = word.isEmpty ? .word : .spseudo
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableiOS26GlassProminentCompat() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
