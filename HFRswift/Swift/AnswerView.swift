import SwiftUI
import UIKit
import PhotosUI

struct AnswerView: View {
    let topicURL: URL?
    let title: String
    let requiresSubject: Bool
    let initialRecipient: String?
    private let replyPostingService: any ReplyPostingService
    private let smileyCatalogLoader: ReplySmileyCatalogLoading
    private let imageUploadService: any ReplyImageUploadService
    private let onPostSuccess: ((ReplyPostingResult) -> Void)?
    @Environment(\.appThemePalette) private var themePalette
    @Environment(\.dismiss) private var dismiss

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool

    @AppStorage("haptics") private var hapticsEnabled = true
    @State private var composerState: ReplyComposerState
    @State private var composerSubject: String
    @State private var composerRecipient: String?
    @State private var defaultSmileys: [ReplySmiley] = []
    @State private var favoriteSmileys: [ReplySmiley] = []
    @State private var imageUploadPreferences: RehostPreferences
    @State private var uploadedImages: [RehostUploadedImage]
    @State private var selectedRangeUTF16: NSRange = NSRange(location: 0, length: 0)
    @State private var isComposerFocused = false
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []
    @State private var pendingHistoryMutationsToSkip = 0

    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastIsSuccess: Bool = true
    @State private var isImageUploading = false
    @State private var imageUploadError: String?
    @State private var imageUploadTask: Task<Void, Never>?

    init(
        topicURL: URL?,
        title: String = "Répondre",
        requiresSubject: Bool = false,
        initialRecipient: String? = nil,
        replyPostingService: any ReplyPostingService = ForumReplyPostingService(),
        smileyCatalogLoader: ReplySmileyCatalogLoading = BundleReplySmileyCatalogLoader(),
        imageUploadService: any ReplyImageUploadService = Img3ReplyImageUploadService(),
        onPostSuccess: ((ReplyPostingResult) -> Void)? = nil,
        composerDraftText: Binding<String>,
        isComposerPresented: Binding<Bool>
    ) {
        self.topicURL = topicURL
        self.title = title
        self.requiresSubject = requiresSubject
        self.initialRecipient = initialRecipient
        self.replyPostingService = replyPostingService
        self.smileyCatalogLoader = smileyCatalogLoader
        self.imageUploadService = imageUploadService
        self.onPostSuccess = onPostSuccess
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._composerState = State(initialValue: ReplyComposerState(initialMessage: composerDraftText.wrappedValue))
        self._composerSubject = State(initialValue: "")
        self._composerRecipient = State(initialValue: initialRecipient)
        self._imageUploadPreferences = State(initialValue: RehostPreferencesStore.load())
        self._uploadedImages = State(initialValue: RehostUploadHistoryStore.load())
    }

    private var presentedComposerPanel: Binding<ReplyComposerPanel?> {
        Binding(
            get: {
                // .favoriteSmileys est géré en overlay inline, pas via sheet
                let panel = composerState.activePanel
                guard panel != .none && panel != .favoriteSmileys else { return nil }
                return panel
            },
            set: { composerState.activePanel = $0 ?? .none }
        )
    }

    var body: some View {
        composerContent
            .overlay {
                if composerState.activePanel == .favoriteSmileys {
                    FavoriteSmileyPickerView(
                        smileys: favoriteSmileys,
                        onSelect: { selectedSmiley in
                            insertSmileyCode(selectedSmiley.code)
                            composerState.activePanel = .none
                        },
                        onClose: {
                            composerState.activePanel = .none
                        }
                    )
                }
            }
            .overlay(alignment: .top) {
                if showToast {
                    ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
    }

    private var composerContent: some View {
        VStack(spacing: 0) {
            composerHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if showsComposerMetadata {
                composerMetadataSection
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            ReplyTextEditor(
                text: $composerState.message,
                selectedRange: $selectedRangeUTF16,
                isFocused: $isComposerFocused
            )
                .padding(12)
                .composerEditorStyle()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            composerToolbar
        }
        .sheet(item: presentedComposerPanel) { panel in
            switch panel {
            case .defaultSmileys:
                SmileyPickerView(title: "Smileys", smileys: defaultSmileys) { selectedSmiley in
                    insertSmileyCode(selectedSmiley.code)
                    composerState.activePanel = .none
                }
                .presentationDetents([.large])
            case .imageInsertion:
                ReplyImageInsertionView(
                    preferences: $imageUploadPreferences,
                    uploadedImages: $uploadedImages,
                    isUploading: $isImageUploading,
                    uploadError: $imageUploadError,
                    onPickImage: startImageUpload
                ) { snippet in
                    insertSnippet(snippet)
                    composerState.activePanel = .none
                }
                .presentationDetents([.large])
            case .favoriteSmileys, .none:
                EmptyView()
            }
        }
        .onAppear {
            composerState.message = composerDraftText
            undoHistory.removeAll()
            redoHistory.removeAll()
            pendingHistoryMutationsToSkip = 0
            if defaultSmileys.isEmpty {
                defaultSmileys = smileyCatalogLoader.loadDefaultSmileys()
            }
            favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()
            selectedRangeUTF16 = NSRange(location: composerState.message.utf16.count, length: 0)
            DispatchQueue.main.async {
                isComposerFocused = true
            }
        }
        .task(id: topicURL?.absoluteString) {
            await loadComposerContext()
        }
        .onDisappear {
            imageUploadTask?.cancel()
            imageUploadTask = nil
            composerDraftText = composerState.message
        }
        .onChange(of: imageUploadPreferences) { _, newPreferences in
            RehostPreferencesStore.save(newPreferences)
        }
        .onChange(of: uploadedImages) { _, newHistory in
            RehostUploadHistoryStore.save(newHistory)
        }
        .onChange(of: composerState.message) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if pendingHistoryMutationsToSkip > 0 {
                pendingHistoryMutationsToSkip -= 1
                return
            }
            undoHistory.append(oldValue)
            if undoHistory.count > 200 {
                undoHistory.removeFirst(undoHistory.count - 200)
            }
            redoHistory.removeAll()
        }
    }

    private var composerHeader: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 96)

            HStack {
                Button {
                    dismissComposer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18, height: 18)
                        .padding(8)
                }
                .disabled(composerState.isPosting)
                .composerCloseButtonStyle()

                Spacer()

                Button {
                    Task { await postMessage() }
                } label: {
                    if composerState.isPosting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                            .padding(8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 18, height: 18)
                            .padding(8)
                    }
                }
                .disabled(!canSend)
                .composerSendButtonStyle(isEnabled: canSend)
                .accessibilityLabel("Envoyer")
            }
        }
        .frame(height: 44)
    }

    private var composerToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent(spacing: 12)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            toolbarContent(spacing: 10, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func toolbarContent(spacing: CGFloat, vertical: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                toolbarStack(spacing: spacing, vertical: vertical)
            }
        } else {
            toolbarStack(spacing: spacing, vertical: vertical)
        }
    }

    @ViewBuilder
    private func toolbarStack(spacing: CGFloat, vertical: Bool) -> some View {
        if vertical {
            VStack(alignment: .leading, spacing: spacing) {
                composerEditionGroup
                composerInsertionGroup
            }
        } else {
            HStack(alignment: .center, spacing: spacing) {
                composerEditionGroup
                Spacer(minLength: 0)
                composerInsertionGroup
            }
        }
    }

    private var composerInsertionGroup: some View {
        ComposerToolbarGroup {
            ComposerToolbarButton(
                systemImage: "face.smiling",
                accessibilityLabel: "Smileys",
                isDisabled: composerState.isPosting
            ) {
                presentDefaultSmileys()
            }

            ComposerToolbarButton(
                systemImage: "star",
                accessibilityLabel: "Smileys favoris",
                isDisabled: favoriteSmileys.isEmpty || composerState.isPosting
            ) {
                presentFavoriteSmileys()
            }

            ComposerToolbarButton(
                systemImage: "photo",
                accessibilityLabel: "Insérer image",
                isDisabled: composerState.isPosting
            ) {
                presentImageInsertion()
            }
        }
    }

    private var composerEditionGroup: some View {
        ComposerToolbarGroup {
            ComposerToolbarButton(
                systemImage: "xmark.circle",
                accessibilityLabel: "Vider le texte",
                isDisabled: composerState.message.isEmpty || composerState.isPosting,
                isDestructive: true
            ) {
                clearComposer()
            }

            ComposerToolbarButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Annuler",
                isDisabled: undoHistory.isEmpty || composerState.isPosting
            ) {
                performUndo()
            }

            ComposerToolbarButton(
                systemImage: "arrow.uturn.forward",
                accessibilityLabel: "Rétablir",
                isDisabled: redoHistory.isEmpty || composerState.isPosting
            ) {
                performRedo()
            }
        }
    }

    private func presentDefaultSmileys() {
        if defaultSmileys.isEmpty {
            defaultSmileys = smileyCatalogLoader.loadDefaultSmileys()
        }
        composerState.activePanel = .defaultSmileys
    }

    private func presentFavoriteSmileys() {
        favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()
        composerState.activePanel = .favoriteSmileys
    }

    private var showsComposerMetadata: Bool {
        requiresSubject || composerRecipient != nil
    }

    private var canSend: Bool {
        guard composerState.canSend else { return false }
        if requiresSubject {
            return !composerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    @ViewBuilder
    private var composerMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let composerRecipient {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destinataire")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(composerRecipient)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            if requiresSubject {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sujet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if #available(iOS 26.0, *) {
                        TextField("Sujet du MP", text: $composerSubject)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(in: .rect(cornerRadius: 10))
                    } else {
                        TextField("Sujet du MP", text: $composerSubject)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(themePalette.editorBackgroundColor)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func loadComposerContext() async {
        guard let topicURL else { return }
        if let contextLoader = replyPostingService as? any ReplyComposerContextLoading,
           let context = try? await contextLoader.fetchComposerContext(topicURL: topicURL) {
            await MainActor.run {
                if composerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let subject = context.subject {
                    composerSubject = subject
                }
                if composerRecipient == nil, let recipient = context.recipient {
                    composerRecipient = recipient
                }
            }
        } else if let preloader = replyPostingService as? any ReplyComposerContextPreloading {
            await preloader.preloadReplyContext(topicURL: topicURL)
        }
        await MainActor.run {
            favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()
        }
    }

    private func presentImageInsertion() {
        composerState.activePanel = .imageInsertion
    }

    private func startImageUpload(with image: UIImage) {
        imageUploadTask?.cancel()
        isImageUploading = true
        imageUploadError = nil

        let maxDimension = imageUploadPreferences.maxDimension
        imageUploadTask = Task {
            do {
                let uploadedImage = try await imageUploadService.uploadImage(image, maxDimension: maxDimension)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    uploadedImages.insert(uploadedImage, at: 0)
                    isImageUploading = false
                    imageUploadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    isImageUploading = false
                    imageUploadTask = nil
                }
            } catch let error as ReplyImageUploadError {
                await MainActor.run {
                    isImageUploading = false
                    imageUploadError = error.localizedDescription
                    imageUploadTask = nil
                }
            } catch {
                await MainActor.run {
                    isImageUploading = false
                    imageUploadError = "Erreur d'upload."
                    imageUploadTask = nil
                }
            }
        }
    }

    private func insertSmileyCode(_ smileyCode: String) {
        // Legacy composer inserts spaces around smiley codes.
        let snippet = " \(smileyCode) "
        insertSnippet(snippet)
    }

    private func insertSnippet(_ snippet: String) {
        guard !snippet.isEmpty else { return }
        let insertion = ReplyTextInsertionEngine.insert(
            snippet,
            into: composerState.message,
            selectedUTF16Range: selectedRangeUTF16
        )
        composerState.message = insertion.text
        selectedRangeUTF16 = NSRange(location: insertion.cursorLocationUTF16, length: 0)
        isComposerFocused = true
    }

    private func clearComposer() {
        composerState.message = ""
        selectedRangeUTF16 = NSRange(location: 0, length: 0)
        isComposerFocused = true
    }

    private func dismissComposer() {
        if isComposerPresented {
            isComposerPresented = false
        }
        dismiss()
    }

    private func performUndo() {
        guard !undoHistory.isEmpty else { return }
        let currentValue = composerState.message
        let previousValue = undoHistory.removeLast()
        pendingHistoryMutationsToSkip += 1
        redoHistory.append(currentValue)
        composerState.message = previousValue
        selectedRangeUTF16 = NSRange(location: previousValue.utf16.count, length: 0)
        isComposerFocused = true
    }

    private func performRedo() {
        guard !redoHistory.isEmpty else { return }
        let currentValue = composerState.message
        let nextValue = redoHistory.removeLast()
        pendingHistoryMutationsToSkip += 1
        undoHistory.append(currentValue)
        composerState.message = nextValue
        selectedRangeUTF16 = NSRange(location: nextValue.utf16.count, length: 0)
        isComposerFocused = true
    }

    private func postMessage() async {
        guard composerState.beginPosting() else { return }
        defer { composerState.endPosting() }

        guard let topicURL else {
            await MainActor.run {
                triggerPostHaptic(success: false)
            }
            await presentToast(success: false, text: "URL manquante")
            return
        }

        do {
            var formOverrides: [String: String] = [:]
            if requiresSubject {
                formOverrides["sujet"] = composerSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let composerRecipient {
                formOverrides["dest"] = composerRecipient
            }
            let result = try await replyPostingService.postReply(
                message: composerState.message,
                topicURL: topicURL,
                formOverrides: formOverrides
            )
            await MainActor.run {
                onPostSuccess?(result)
            }
            await MainActor.run {
                triggerPostHaptic(success: true)
            }
            await presentToast(success: true, text: "Hooray")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                composerState.resetAfterSuccessfulPost()
                undoHistory.removeAll()
                redoHistory.removeAll()
                pendingHistoryMutationsToSkip = 0
                composerDraftText = ""
                composerSubject = ""
                isComposerFocused = false
                dismissComposer()
            }
        } catch let error as ReplyPostingError {
            await MainActor.run {
                triggerPostHaptic(success: false)
            }
            await presentToast(success: false, text: error.localizedDescription)
        } catch {
            await MainActor.run {
                triggerPostHaptic(success: false)
            }
            await presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
    }

    @MainActor private func triggerPostHaptic(success: Bool) {
        guard resolvedHapticsEnabled() else { return }
        #if canImport(UIKit)
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(success ? .success : .error)

        let impactStyle: UIImpactFeedbackGenerator.FeedbackStyle = success ? .light : .rigid
        let impactGenerator = UIImpactFeedbackGenerator(style: impactStyle)
        impactGenerator.prepare()
        impactGenerator.impactOccurred()
        #endif
    }

    private func resolvedHapticsEnabled() -> Bool {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.object(forKey: "haptics") else {
            return hapticsEnabled
        }
        if let boolValue = rawValue as? Bool {
            return boolValue
        }
        if let numberValue = rawValue as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = rawValue as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        return hapticsEnabled
    }

    @MainActor private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation {
            showToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

private struct ComposerToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 8) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        } else {
            HStack(spacing: 10) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color(uiColor: .tertiarySystemBackground),
                in: .capsule
            )
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 1)
            }
        }
    }
}

private struct ComposerToolbarButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 18, height: 18)
                .padding(8)
                .foregroundStyle(isDestructive ? .red : .primary)
        }
        .composerToolbarButtonStyle(isDisabled: isDisabled)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
    }
}

private extension View {
    @ViewBuilder
    func composerCloseButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonBorderShape(.circle)
                .buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.bordered)
                .clipShape(.circle)
        }
    }

    @ViewBuilder
    func composerSendButtonStyle(isEnabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isEnabled {
                self
                    .buttonBorderShape(.circle)
                    .buttonStyle(.glassProminent)
            } else {
                self
                    .buttonBorderShape(.circle)
                    .buttonStyle(.glass)
            }
        } else {
            if isEnabled {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func composerToolbarButtonStyle(isDisabled: Bool) -> some View {
        self.buttonStyle(.plain)
    }

    /// Fond du composeur : glassEffect sur iOS 26, secondarySystemBackground sinon.
    @ViewBuilder
    func composerEditorStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: 18))
        } else {
            self
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 1)
                }
        }
    }
}

private struct ComposerSheetCloseHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 96)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18, height: 18)
                        .padding(8)
                }
                .composerCloseButtonStyle()
                .accessibilityLabel("Fermer")

                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

private struct SmileyPickerView: View {
    let title: String
    let smileys: [ReplySmiley]
    let onSelect: (ReplySmiley) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 90), spacing: 4)]

    var body: some View {
        VStack(spacing: 0) {
            ComposerSheetCloseHeader(title: title) {
                dismiss()
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(smileys) { smiley in
                        Button {
                            onSelect(smiley)
                            dismiss()
                        } label: {
                            SmileyGridCell(smiley: smiley)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(smiley.code)
                    }
                }
                .padding(8)
            }
        }
        .presentationGlassBackground()
    }
}

// MARK: - Favorite Smiley Picker (avec recherche)

/// Sheet smileys favoris enrichie d'une barre de recherche par mot-clé.
/// - Affiche les favoris par défaut.
/// - Un champ de saisie en bas lance la recherche HFR ; les résultats remplacent la grille.
/// - Un bouton "← Favoris" permet de revenir à l'affichage initial.
/// - L'historique des recherches réussies est proposé en complétion à la saisie suivante.
private struct FavoriteSmileyPickerView: View {
    let smileys: [ReplySmiley]
    let onSelect: (ReplySmiley) -> Void
    let onClose: () -> Void
    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 90), spacing: 4)]
    private let searchService: any SmileySearching = HFRSmileySearchService()

    enum DisplayMode: Equatable {
        case favorites
        case results([ReplySmiley])
        case empty
        static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
            switch (lhs, rhs) {
            case (.favorites, .favorites), (.empty, .empty): return true
            case (.results(let a), .results(let b)): return a == b
            default: return false
            }
        }
    }

    @State private var displayMode: DisplayMode = .favorites
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var recentSuggestions: [SmileySearchHistoryEntry] = []
    @State private var topSuggestions: [SmileySearchHistoryEntry] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    private var displayedSmileys: [ReplySmiley] {
        if case .results(let r) = displayMode { return r }
        return smileys
    }
    private var isShowingResults: Bool {
        if case .favorites = displayMode { return false }
        return true
    }
    private var hasSuggestions: Bool { !recentSuggestions.isEmpty || !topSuggestions.isEmpty }
    private var canSearch: Bool { searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
    private var showSuggestions: Bool { hasSuggestions && displayMode == .favorites }

    /// Chips à afficher : récents seulement si pas de texte, mélange récent+fréquent sinon.
    private var suggestionChips: [SmileySearchHistoryEntry] {
        if searchText.isEmpty {
            return Array(recentSuggestions.prefix(4))
        }
        let recentTexts = Set(recentSuggestions.map { $0.text })
        let uniqueTop = topSuggestions.filter { !recentTexts.contains($0.text) }
        return Array((recentSuggestions + uniqueTop).prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposerSheetCloseHeader(title: "Smileys favoris") {
                closePanel()
            }

            ScrollView {
                if case .empty = displayMode {
                    smileyEmptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(displayedSmileys) { smiley in
                            Button {
                                selectSmiley(smiley)
                            } label: {
                                SmileyGridCell(smiley: smiley)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(smiley.code)
                        }
                    }
                    .padding(8)
                }
            }

            if showSuggestions && !suggestionChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestionChips) { entry in
                            Button {
                                isSearchFieldFocused = false
                                searchText = entry.text
                                performSearch()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(entry.text)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .smileyChipStyle()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            searchBarRow
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .onAppear {
            isSearchFieldFocused = false
            refreshSuggestions()
        }
        .onChange(of: searchText) { _, _ in refreshSuggestions() }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Search bar row

    private var searchBarRow: some View {
        HStack(spacing: 8) {
            // Bouton retour aux favoris (visible en mode résultats)
            if isShowingResults {
                Button(action: clearSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(8)
                }
                .accessibilityLabel("Retour aux favoris")
                .smileySearchButtonStyle()
            }

            // Champ de saisie
            HStack {
                TextField("Rechercher un smiley…", text: $searchText)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        refreshSuggestions()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .smileySearchFieldStyle()

            // Bouton lancer la recherche ou spinner
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 36, height: 36)
            } else {
                Button {
                    performSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(8)
                }
                .disabled(!canSearch)
                .opacity(canSearch ? 1 : 0.4)
                .accessibilityLabel("Rechercher")
                .smileySearchButtonStyle()
            }
        }
    }

    // MARK: - Empty state

    private var smileyEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Aucun smiley trouvé")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Essayez avec un autre mot-clé.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Button("Retour aux favoris", action: clearSearch)
                .font(.subheadline)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.bottom, 20)
    }

    // MARK: - Logic

    private func refreshSuggestions() {
        recentSuggestions = SmileySearchHistoryStore.recentSuggestions(matching: searchText)
        topSuggestions = SmileySearchHistoryStore.topSuggestions(matching: searchText)
    }

    @MainActor
    private func performAfterSearchFieldBlur(_ action: @escaping @MainActor () -> Void) {
        let hadFocus = isSearchFieldFocused
        isSearchFieldFocused = false
        if hadFocus {
            Task { @MainActor in
                await Task.yield()
                action()
            }
        } else {
            action()
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        isSearchFieldFocused = false
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            do {
                let results = try await searchService.search(query: query)
                guard !Task.isCancelled else { return }
                SmileySearchHistoryStore.record(query: query, resultCount: results.count)
                await MainActor.run {
                    isSearching = false
                    displayMode = results.isEmpty ? .empty : .results(results)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSearching = false
                    displayMode = .empty
                }
            }
        }
    }

    private func clearSearch() {
        isSearchFieldFocused = false
        searchTask?.cancel()
        isSearching = false
        displayMode = .favorites
    }

    private func closePanel() {
        Task { @MainActor in
            performAfterSearchFieldBlur {
                onClose()
            }
        }
    }

    private func selectSmiley(_ smiley: ReplySmiley) {
        Task { @MainActor in
            performAfterSearchFieldBlur {
                onSelect(smiley)
            }
        }
    }
}

// MARK: - View modifiers spécifiques à la recherche de smileys

private extension View {
    /// Fond du champ de texte de recherche.
    @ViewBuilder
    func smileySearchFieldStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: 10))
        } else {
            self
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                }
        }
    }

    /// Style des boutons icône de la barre de recherche (retour, loupe).
    @ViewBuilder
    func smileySearchButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonBorderShape(.circle)
                .buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.bordered)
                .clipShape(.circle)
        }
    }

    /// Style des chips de suggestions de recherche (capsule Liquid Glass).
    @ViewBuilder
    func smileyChipStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.thinMaterial, in: .capsule)
                .overlay(Capsule().stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))
        }
    }
}

private struct SmileyGridCell: View {
    let smiley: ReplySmiley
    @Environment(\.appThemePalette) private var themePalette

    var body: some View {
        SmileyThumbnailView(smiley: smiley)
            .frame(width: 70, height: 50)       // taille max des images smiley
            .frame(maxWidth: .infinity, minHeight: 58) // la cell remplit la colonne et centre l'image
            .background(themePalette.tertiaryBackgroundColor)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

private struct SmileyThumbnailView: UIViewRepresentable {
    let smiley: ReplySmiley

    func makeUIView(context: Context) -> UIImageView {
        // Utilise SDAnimatedImageView si disponible pour animer les GIFs correctement.
        let imageView: UIImageView
        if let animatedClass = NSClassFromString("SDAnimatedImageView") as? NSObject.Type,
           let animatedView = animatedClass.init() as? UIImageView {
            imageView = animatedView
        } else {
            imageView = UIImageView()
        }
        imageView.contentMode = .center
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.update(uiView, with: smiley)
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        coordinator.cancelPendingWork()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private static let bundledImageCache = NSCache<NSString, UIImage>()
        private static let remoteImageCache = NSCache<NSString, UIImage>()
        private var currentSmileyID: String?
        private var loadTask: Task<Void, Never>?

        func update(_ imageView: UIImageView, with smiley: ReplySmiley) {
            guard currentSmileyID != smiley.id else { return }
            currentSmileyID = smiley.id
            loadTask?.cancel()

            imageView.image = nil

            switch smiley.imageSource {
            case .bundledGIF(let filename):
                imageView.image = loadBundledGIF(named: filename)
                imageView.startAnimating()
            case .remote(let url):
                let cacheKey = url.absoluteString as NSString
                if let cached = Self.remoteImageCache.object(forKey: cacheKey) {
                    imageView.image = cached
                    imageView.startAnimating()
                    return
                }

                let smileyID = smiley.id
                loadTask = Task { [weak imageView] in
                    guard let image = await self.loadRemoteGIF(from: url) else { return }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.currentSmileyID == smileyID else { return }
                        imageView?.image = image
                        imageView?.startAnimating()
                    }
                }
            case .none:
                imageView.image = nil
            }
        }

        func cancelPendingWork() {
            loadTask?.cancel()
            loadTask = nil
        }

        private func loadBundledGIF(named filename: String) -> UIImage? {
            let key = filename as NSString
            if let cached = Self.bundledImageCache.object(forKey: key) {
                return cached
            }

            let nsFilename = filename as NSString
            let baseName = nsFilename.deletingPathExtension
            let fileExtension = nsFilename.pathExtension.isEmpty ? "gif" : nsFilename.pathExtension

            let bundle = Bundle.main
            let directPath = bundle.path(forResource: baseName, ofType: fileExtension)
            let nestedPath = bundle.path(
                forResource: baseName,
                ofType: fileExtension,
                inDirectory: "Assets/HFR/Smilies"
            )
            guard let path = directPath ?? nestedPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = decodeGIFImage(from: data) else {
                return nil
            }

            Self.bundledImageCache.setObject(image, forKey: key)
            return image
        }

        private func loadRemoteGIF(from url: URL) async -> UIImage? {
            let cacheKey = url.absoluteString as NSString
            if let cached = Self.remoteImageCache.object(forKey: cacheKey) {
                return cached
            }

            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = decodeGIFImage(from: data) else {
                return nil
            }

            Self.remoteImageCache.setObject(image, forKey: cacheKey)
            return image
        }

        private func decodeGIFImage(from data: Data) -> UIImage? {
            // Aligne sur l'approche de MessagesView : sd_animatedGIFWithData: en priorité,
            // puis fallback CGImageSource multi-frames.
            let selector = NSSelectorFromString("sd_animatedGIFWithData:")
            let imageClass: AnyObject = UIImage.self
            if imageClass.responds(to: selector),
               let unmanaged = imageClass.perform(selector, with: data),
               let image = unmanaged.takeUnretainedValue() as? UIImage {
                return image
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 1 else { return UIImage(data: data) }

            var frames: [UIImage] = []
            var totalDuration: Double = 0
            // Les smileys GIF sont des assets 1x — scale: 1.0 conserve leur taille naturelle.
            for index in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                totalDuration += Self.frameDuration(at: index, in: source)
                frames.append(UIImage(cgImage: cgImage, scale: 1.0, orientation: .up))
            }
            guard !frames.isEmpty else { return UIImage(data: data) }
            if totalDuration <= 0 { totalDuration = Double(frames.count) * 0.1 }
            return UIImage.animatedImage(with: frames, duration: totalDuration)
        }

        private static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else { return 0.1 }
            let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
            let duration = unclampedDelay ?? delay ?? 0.1
            return duration < 0.011 ? 0.1 : duration
        }
    }
}

private struct ReplyImageInsertionView: View {
    @Binding var preferences: RehostPreferences
    @Binding var uploadedImages: [RehostUploadedImage]
    @Binding var isUploading: Bool
    @Binding var uploadError: String?
    let onPickImage: (UIImage) -> Void
    let onInsertSnippet: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemePalette) private var themePalette

    @State private var manualURL = ""
    @State private var presentedPicker: ReplyPresentedImagePicker?
    @State private var photoViewerDestination: ReplyPhotoViewerDestination?
    @FocusState private var isManualURLFocused: Bool

    private var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var canInsertManualURL: Bool {
        let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    private var prefersProminentPrimaryButtons: Bool {
        themePalette.colorScheme == .light
    }

    private var secondaryControlTintColor: Color {
        themePalette.colorScheme == .light
            ? Color(uiColor: .systemGray3)
            : themePalette.actionTintColor
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposerSheetCloseHeader(title: "Insérer image") {
                dismiss()
            }

            List {
                Section("Upload") {
                    HStack(spacing: 12) {
                        Button {
                            isManualURLFocused = false
                            uploadError = nil
                            presentedPicker = .photoLibrary
                        } label: {
                            Label("Photos", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(prefersProminentPrimaryButtons ? .white : .primary)
                        }
                        .controlSize(.large)
                        .replyTintedActionButtonStyle(
                            useProminent: prefersProminentPrimaryButtons,
                            tint: themePalette.actionTintColor
                        )
                        .disabled(isUploading)

                        Button {
                            isManualURLFocused = false
                            guard canUseCamera else {
                                uploadError = "Caméra indisponible sur cet appareil."
                                return
                            }
                            uploadError = nil
                            presentedPicker = .camera
                        } label: {
                            Label("Caméra", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(prefersProminentPrimaryButtons ? .white : .primary)
                        }
                        .controlSize(.large)
                        .replyTintedActionButtonStyle(
                            useProminent: prefersProminentPrimaryButtons,
                            tint: themePalette.actionTintColor
                        )
                        .disabled(!canUseCamera || isUploading)
                    }
                    .buttonStyle(.borderless)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dimension maximale")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Dimension maximale", selection: $preferences.maxDimension) {
                            ForEach(RehostUploadMaxDimension.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(secondaryControlTintColor)
                    }

                    if isUploading {
                        ProgressView("Upload en cours...")
                    }

                    if let uploadError, !uploadError.isEmpty {
                        Text(uploadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Images uploadées") {
                    Picker("Type de bbcode", selection: $preferences.bbCodeMode) {
                        ForEach(RehostBBCodeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(secondaryControlTintColor)

                    if uploadedImages.isEmpty {
                        Text("Aucune image uploadée.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(uploadedImages) { uploadedImage in
                            ReplyUploadedImageRow(
                                image: uploadedImage,
                                mode: preferences.bbCodeMode,
                                onPreviewImage: { previewImage(uploadedImage) }
                            ) { selectedVariant in
                                insertUploadedImage(uploadedImage, variant: selectedVariant)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeUploadedImage(uploadedImage)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("URL manuelle") {
                    TextField("https://...", text: $manualURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($isManualURLFocused)

                    Button("Insérer") {
                        insertManualURL()
                    }
                    .replyTintedActionButtonStyle(
                        useProminent: false,
                        tint: secondaryControlTintColor
                    )
                    .foregroundStyle(.primary)
                    .disabled(!canInsertManualURL)
                }
            }
            .padding(.top, 8)
        }
        .fullScreenCover(item: $presentedPicker) { picker in
            switch picker {
            case .photoLibrary:
                ReplyPhotoLibraryPicker(
                    onCancel: {
                        presentedPicker = nil
                    },
                    onPick: { selectedImage in
                        presentedPicker = nil
                        onPickImage(selectedImage)
                    }
                )
                .ignoresSafeArea()
            case .camera:
                ReplyUIKitImagePicker(
                    sourceType: .camera,
                    onCancel: {
                        presentedPicker = nil
                    },
                    onPick: { selectedImage in
                        presentedPicker = nil
                        onPickImage(selectedImage)
                    }
                )
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $photoViewerDestination) { destination in
            FullScreenPhotoViewer(url: destination.url, presentationID: destination.id)
        }
        .presentationGlassBackground()
    }

    private func insertUploadedImage(_ image: RehostUploadedImage, variant: RehostImageSizeVariant) {
        guard let snippet = image.formattedSnippet(for: variant, mode: preferences.bbCodeMode) else {
            return
        }
        onInsertSnippet(snippet)
        dismiss()
    }

    private func removeUploadedImage(_ image: RehostUploadedImage) {
        uploadedImages.removeAll { $0.id == image.id }
    }

    private func previewImage(_ image: RehostUploadedImage) {
        let candidateURLs = [image.fullURL, image.mediumURL, image.previewURL, image.miniURL]
        for candidate in candidateURLs {
            guard let candidate, let url = URL(string: candidate) else { continue }
            photoViewerDestination = ReplyPhotoViewerDestination(url: url)
            return
        }
    }

    private func insertManualURL() {
        let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let manualImage = RehostUploadedImage(
            fullWidth: nil,
            fullHeight: nil,
            fullURL: trimmed,
            mediumURL: nil,
            previewURL: nil,
            miniURL: nil
        )
        guard let snippet = manualImage.formattedSnippet(for: .full, mode: preferences.bbCodeMode) else {
            return
        }
        onInsertSnippet(snippet)
        dismiss()
    }
}

private enum ReplyPresentedImagePicker: String, Identifiable {
    case photoLibrary
    case camera

    var id: String { rawValue }
}

private struct ReplyPhotoViewerDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ReplyUploadedImageRow: View {
    let image: RehostUploadedImage
    let mode: RehostBBCodeMode
    let onPreviewImage: () -> Void
    let onInsertVariant: (RehostImageSizeVariant) -> Void
    @Environment(\.appThemePalette) private var themePalette

    private var secondaryControlTintColor: Color {
        themePalette.colorScheme == .light
            ? Color(uiColor: .systemGray3)
            : themePalette.actionTintColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onPreviewImage) {
                    AsyncImage(url: URL(string: image.thumbnailURL)) { phase in
                        switch phase {
                        case .success(let preview):
                            preview
                                .resizable()
                                .scaledToFill()
                        default:
                            themePalette.controlBackgroundColor
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Afficher l'image")

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(image.maxDimensionText ?? "Image")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Text(image.fullURL)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                ForEach(image.availableVariants) { variant in
                    Button {
                        onInsertVariant(variant)
                    } label: {
                        Text(variant.title)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .replyTintedActionButtonStyle(
                        useProminent: false,
                        tint: secondaryControlTintColor
                    )
                    .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private extension View {
    @ViewBuilder
    func replyTintedActionButtonStyle(useProminent: Bool, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            if useProminent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if useProminent {
                self
                    .tint(tint)
                    .buttonStyle(.borderedProminent)
            } else {
                self
                    .tint(tint)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct ReplyUIKitImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = sourceType
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        if uiViewController.sourceType != sourceType,
           UIImagePickerController.isSourceTypeAvailable(sourceType) {
            uiViewController.sourceType = sourceType
        }
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCancel: () -> Void
        private let onPick: (UIImage) -> Void

        init(onCancel: @escaping () -> Void, onPick: @escaping (UIImage) -> Void) {
            self.onCancel = onCancel
            self.onPick = onPick
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [onCancel] in
                onCancel()
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true) { [onCancel] in
                    onCancel()
                }
                return
            }
            picker.dismiss(animated: true) { [onPick] in
                onPick(image)
            }
        }
    }
}

private struct ReplyPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onCancel: () -> Void
        private let onPick: (UIImage) -> Void

        init(onCancel: @escaping () -> Void, onPick: @escaping (UIImage) -> Void) {
            self.onCancel = onCancel
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                picker.dismiss(animated: true) { [onCancel] in
                    onCancel()
                }
                return
            }

            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                picker.dismiss(animated: true) { [onCancel] in
                    onCancel()
                }
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [onPick, onCancel] object, _ in
                DispatchQueue.main.async {
                    guard let image = object as? UIImage else {
                        picker.dismiss(animated: true) {
                            onCancel()
                        }
                        return
                    }
                    picker.dismiss(animated: true) {
                        onPick(image)
                    }
                }
            }
        }
    }
}

private struct ReplyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.keyboardDismissMode = .none
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        let boundedSelection = clampedRange(selectedRange, textUTF16Count: uiView.text.utf16.count)
        if uiView.selectedRange != boundedSelection {
            uiView.selectedRange = boundedSelection
        }

        if isFocused {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func clampedRange(_ range: NSRange, textUTF16Count: Int) -> NSRange {
        let maxLocation = max(min(range.location, textUTF16Count), 0)
        let maxLength = max(min(range.length, textUTF16Count - maxLocation), 0)
        return NSRange(location: maxLocation, length: maxLength)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReplyTextEditor

        init(_ parent: ReplyTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Keep focus state stable; explicit blur is driven by view actions (send/dismiss).
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !NSEqualRanges(parent.selectedRange, textView.selectedRange) {
                parent.selectedRange = textView.selectedRange
            }
        }
    }
}

private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

private struct AnswerViewPreviewWrapper: View {
    @State private var draft: String = ""
    @State private var presented: Bool = false

    var body: some View {
        NavigationStack {
            AnswerView(
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1#t100")!,
                composerDraftText: $draft,
                isComposerPresented: $presented
            )
        }
    }
}

#Preview {
    AnswerViewPreviewWrapper()
}
