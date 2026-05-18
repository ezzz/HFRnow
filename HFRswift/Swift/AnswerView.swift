import SwiftUI
import UIKit
import PhotosUI
import GiphyUISDK

// MARK: - Focus Request
//
// Pattern: a reference-type token carries the "please focus" intent; a companion
// @State Int (focusTrigger) causes SwiftUI to re-invoke updateUIView so the token
// can be consumed at the right moment — after the view hierarchy is stable.
//
// Why not @Binding<Bool>? Setting it back to false from updateUIView triggers
// another render, which calls updateUIView again → infinite loop.
// Why not DispatchQueue.main.async? Arbitrary delay, breaks with fast interactions.

private final class TextEditorFocusRequest {
    var pending = false
    func request() { pending = true }
    /// Atomically consumes the request. Call once inside updateUIView.
    func consume() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }
}

// MARK: - AnswerView

struct AnswerView: View {
    enum ComposerDraftPersistence {
        static func draftAfterDismiss(currentMessage: String, existingDraft: String, persistsDraft: Bool) -> String {
            persistsDraft ? currentMessage : existingDraft
        }

        static func draftAfterSuccessfulPost(existingDraft: String, persistsDraft: Bool) -> String {
            persistsDraft ? "" : existingDraft
        }
    }

    // MARK: Public interface
    let topicURL: URL?
    let title: String
    let requiresSubject: Bool
    let requiresSubcategory: Bool
    let subjectCharacterLimit: Int?
    let subjectPlaceholder: String
    let initialRecipient: String?
    let initialMessage: String
    let persistsComposerDraft: Bool
    private let replyPostingService: any ReplyPostingService
    private let smileyCatalogLoader: ReplySmileyCatalogLoading
    private let imageUploadService: any ReplyImageUploadService
    private let onPostSuccess: ((ReplyPostingResult) -> Void)?

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool

    // MARK: Environment
    @Environment(\.appThemePalette) private var themePalette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTextSizeScale.key) private var textSizeScaleRawValue = AppTextSizeScale.standard.rawValue

    // MARK: Composer state
    @State private var message: String
    @State private var composerSubject = ""
    @State private var composerRecipient: String?
    @State private var contextShowsSubjectField = false
    @State private var contextShowsSubcategoryPicker = false
    @State private var selectedSubcategoryID: String?
    @State private var subcategoryOptions: [ReplyComposerSubcategoryOption] = []
    @State private var isPosting = false
    @State private var selectedRangeUTF16 = NSRange(location: 0, length: 0)

    // MARK: Undo / Redo
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []
    @State private var pendingHistoryMutationsToSkip = 0

    // MARK: Smileys
    @State private var defaultSmileys: [ReplySmiley] = []
    @State private var forumFavoriteSmileys: [ReplySmiley] = []
    @State private var appFavoriteSmileys: [ReplySmiley] = []
    @State private var smileyPickerState = SmileyPickerSessionState()

    // MARK: Image upload
    @State private var imageUploadPreferences: RehostPreferences
    @State private var uploadedImages: [RehostUploadedImage]
    @State private var isImageUploading = false
    @State private var imageUploadError: String?
    @State private var imageUploadTask: Task<Void, Never>?

    // MARK: Focus
    // @State preserves the same class instance across SwiftUI re-renders.
    @State private var focusRequest = TextEditorFocusRequest()
    // Incrementing this value triggers updateUIView on ReplyTextEditor so the
    // focus request above is consumed and becomeFirstResponder is called at the
    // correct moment (view hierarchy stable, no sheet animating over the editor).
    @State private var focusTrigger = 0

    // MARK: Panel
    @State private var isSmileyPickerPresented = false
    @State private var isImageInsertionPresented = false
    @State private var isGiphyPresented = false
    @State private var didLockInterfaceOrientation = false

    // MARK: Toast
    @State private var showToast = false
    @State private var toastText = ""
    @State private var toastIsSuccess = true

    // MARK: Init

    init(
        topicURL: URL?,
        title: String = "Répondre",
        requiresSubject: Bool = false,
        requiresSubcategory: Bool = false,
        subjectCharacterLimit: Int? = nil,
        subjectPlaceholder: String = "Sujet du MP",
        initialRecipient: String? = nil,
        initialMessage: String = "",
        persistsComposerDraft: Bool = true,
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
        self.requiresSubcategory = requiresSubcategory
        self.subjectCharacterLimit = subjectCharacterLimit
        self.subjectPlaceholder = subjectPlaceholder
        self.initialRecipient = initialRecipient
        self.initialMessage = initialMessage
        self.persistsComposerDraft = persistsComposerDraft
        self.replyPostingService = replyPostingService
        self.smileyCatalogLoader = smileyCatalogLoader
        self.imageUploadService = imageUploadService
        self.onPostSuccess = onPostSuccess
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._message = State(initialValue: initialMessage)
        self._composerRecipient = State(initialValue: initialRecipient)
        self._imageUploadPreferences = State(initialValue: RehostPreferencesStore.load())
        self._uploadedImages = State(initialValue: RehostUploadHistoryStore.load())
    }

    // MARK: Computed

    private var canSend: Bool {
        guard !isPosting, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if showsSubjectField,
           composerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if showsSubcategoryPicker && subcategoryOptions.isEmpty {
            return false
        }
        if showsSubcategoryPicker {
            return selectedSubcategoryID?.isEmpty == false
        }
        return true
    }

    private var showsSubjectField: Bool { requiresSubject || contextShowsSubjectField }

    private var showsSubcategoryPicker: Bool {
        requiresSubcategory || contextShowsSubcategoryPicker || !subcategoryOptions.isEmpty
    }

    private var effectiveSubjectCharacterLimit: Int? {
        subjectCharacterLimit ?? (showsSubjectField ? 70 : nil)
    }

    private var showsMetadata: Bool {
        composerRecipient != nil || showsSubjectField || showsSubcategoryPicker
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            composerHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if showsMetadata {
                metadataSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            ReplyTextEditor(
                text: $message,
                selectedRange: $selectedRangeUTF16,
                focusRequest: focusRequest,
                focusTrigger: focusTrigger,
                textSizeScaleRawValue: textSizeScaleRawValue,
                onBBCodeAction: performBBCode,
                onSplitQuote: performSplitQuote
            )
            .padding(12)
            .composerEditorStyle()
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            composerToolbar
        }
        // All three panels are sheets.
        // onDismiss fires after the sheet animation completes — the editor is back
        // in the view hierarchy and can safely become first responder.
        .sheet(isPresented: $isSmileyPickerPresented, onDismiss: requestEditorFocus) {
            smileyPickerPanel
        }
        .sheet(isPresented: $isImageInsertionPresented, onDismiss: requestEditorFocus) {
            imageInsertionPanel
        }
        .fullScreenCover(isPresented: $isGiphyPresented, onDismiss: requestEditorFocus) {
            GiphyPanel {
                insertSnippet($0)
            } onDismiss: {
                isGiphyPresented = false
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if showToast {
                ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
        .onAppear {
            if !didLockInterfaceOrientation {
                HFRSwiftOrientationPolicy.lockForAnswerViewIfNeeded()
                didLockInterfaceOrientation = true
            }
            message = initialMessage
            undoHistory.removeAll()
            redoHistory.removeAll()
            pendingHistoryMutationsToSkip = 0
            if defaultSmileys.isEmpty { defaultSmileys = smileyCatalogLoader.loadDefaultSmileys() }
            reloadFavoriteSmileys()
            selectedRangeUTF16 = NSRange(location: message.utf16.count, length: 0)
            requestEditorFocus()
        }
        .task(id: topicURL?.absoluteString) {
            await loadComposerContext()
        }
        .onDisappear {
            if didLockInterfaceOrientation {
                HFRSwiftOrientationPolicy.unlockForAnswerViewIfNeeded()
                didLockInterfaceOrientation = false
            }
            imageUploadTask?.cancel()
            imageUploadTask = nil
            smileyPickerState = SmileyPickerSessionState()
            composerDraftText = ComposerDraftPersistence.draftAfterDismiss(
                currentMessage: message,
                existingDraft: composerDraftText,
                persistsDraft: persistsComposerDraft
            )
        }
        .onChange(of: imageUploadPreferences) { _, new in RehostPreferencesStore.save(new) }
        .onChange(of: uploadedImages) { _, new in RehostUploadHistoryStore.save(new) }
        .onChange(of: composerSubject) { _, new in
            enforceSubjectCharacterLimit(new)
        }
        .onChange(of: message) { old, new in
            guard old != new else { return }
            if pendingHistoryMutationsToSkip > 0 {
                pendingHistoryMutationsToSkip -= 1
                return
            }
            undoHistory.append(old)
            if undoHistory.count > 200 { undoHistory.removeFirst(undoHistory.count - 200) }
            redoHistory.removeAll()
        }
    }

    // MARK: Panel content

    private var smileyPickerPanel: some View {
        CombinedSmileyPickerView(
            defaultSmileys: defaultSmileys,
            forumFavoriteSmileys: forumFavoriteSmileys,
            appFavoriteSmileys: appFavoriteSmileys,
            sessionState: $smileyPickerState,
            onSelect: { smiley in
                insertSmileyCode(smiley.code)
            },
            onToggleFavorite: { smiley, add in
                updateFavoriteSmiley(smiley, add: add)
            },
            onFetchKeywords: { code in
                await fetchSmileyKeywords(code: code)
            }
        )
        .presentationDetents([.large])
    }

    private var imageInsertionPanel: some View {
        ReplyImageInsertionView(
            preferences: $imageUploadPreferences,
            uploadedImages: $uploadedImages,
            isUploading: $isImageUploading,
            uploadError: $imageUploadError,
            onPickImage: startImageUpload
        ) { snippet in
            insertSnippet(snippet)
        }
        .presentationDetents([.large])
    }

    // MARK: Focus

    private func requestEditorFocus() {
        focusRequest.request()
        focusTrigger &+= 1
    }

    // MARK: Header

    private var composerHeader: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 96)

            HStack {
                Button { dismissComposer() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18, height: 18)
                        .padding(8)
                }
                .disabled(isPosting)
                .composerCloseButtonStyle()

                Spacer()

                Button { Task { await postMessage() } } label: {
                    if isPosting {
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

    // MARK: Metadata (sujet / sous-catégorie / destinataire)

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let recipient = composerRecipient {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destinataire").font(.caption).foregroundStyle(.secondary)
                    Text(recipient).font(.body).foregroundStyle(.primary)
                }
            }
            if showsSubjectField {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sujet").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let limit = effectiveSubjectCharacterLimit {
                            Text("\(min(composerSubject.count, limit))/\(limit)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    metadataTextField
                }
            }
            if showsSubcategoryPicker {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sous-catégorie").font(.caption).foregroundStyle(.secondary)
                    if subcategoryOptions.isEmpty {
                        Text("Chargement...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(themePalette.editorBackgroundColor)
                            .clipShape(.rect(cornerRadius: 10))
                    } else {
                        Picker("Sous-catégorie", selection: subcategorySelection) {
                            ForEach(subcategoryOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(themePalette.editorBackgroundColor)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metadataTextField: some View {
        if #available(iOS 26.0, *) {
            TextField(subjectPlaceholder, text: $composerSubject)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(in: .rect(cornerRadius: 10))
        } else {
            TextField(subjectPlaceholder, text: $composerSubject)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(themePalette.editorBackgroundColor)
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var subcategorySelection: Binding<String> {
        Binding(
            get: { selectedSubcategoryID ?? subcategoryOptions.first?.id ?? "" },
            set: { selectedSubcategoryID = $0 }
        )
    }

    // MARK: Toolbar

    private var composerToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(spacing: 12)
                .padding(.horizontal, 16).padding(.vertical, 12)
            toolbarColumn(spacing: 10)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func toolbarRow(spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                HStack(alignment: .center, spacing: spacing) {
                    editionGroup; Spacer(minLength: 0); insertionGroup
                }
            }
        } else {
            HStack(alignment: .center, spacing: spacing) {
                editionGroup; Spacer(minLength: 0); insertionGroup
            }
        }
    }

    @ViewBuilder
    private func toolbarColumn(spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    editionGroup; insertionGroup
                }
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                editionGroup; insertionGroup
            }
        }
    }

    private var editionGroup: some View {
        ComposerToolbarGroup {
            ComposerToolbarButton(
                systemImage: "xmark.circle",
                accessibilityLabel: "Vider le texte",
                isDisabled: message.isEmpty || isPosting,
                isDestructive: true
            ) { clearComposer() }
            ComposerToolbarButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Annuler",
                isDisabled: undoHistory.isEmpty || isPosting
            ) { performUndo() }
            ComposerToolbarButton(
                systemImage: "arrow.uturn.forward",
                accessibilityLabel: "Rétablir",
                isDisabled: redoHistory.isEmpty || isPosting
            ) { performRedo() }
        }
    }

    private var insertionGroup: some View {
        ComposerToolbarGroup {
            ComposerToolbarButton(
                systemImage: "face.smiling",
                accessibilityLabel: "Smileys",
                isDisabled: isPosting
            ) {
                if defaultSmileys.isEmpty { defaultSmileys = smileyCatalogLoader.loadDefaultSmileys() }
                reloadFavoriteSmileys()
                isSmileyPickerPresented = true
            }
            ComposerToolbarButton(
                systemImage: "g.circle",
                accessibilityLabel: "GIF Giphy",
                isDisabled: isPosting
            ) {
                isGiphyPresented = true
            }
            ComposerToolbarButton(
                systemImage: "photo",
                accessibilityLabel: "Insérer image",
                isDisabled: isPosting
            ) {
                isImageInsertionPresented = true
            }
        }
    }

    // MARK: Insertion

    private func insertSmileyCode(_ code: String) {
        insertSnippet(" \(code) ")
    }

    private func insertSnippet(_ snippet: String) {
        guard !snippet.isEmpty else { return }
        let result = ReplyTextInsertionEngine.insert(snippet, into: message, selectedUTF16Range: selectedRangeUTF16)
        message = result.text
        selectedRangeUTF16 = NSRange(location: result.cursorLocationUTF16, length: 0)
        // Focus is restored via the sheet's onDismiss — no action needed here.
    }

    private func reloadFavoriteSmileys() {
        forumFavoriteSmileys = smileyCatalogLoader.loadForumFavoriteSmileys()
        appFavoriteSmileys = smileyCatalogLoader.loadAppFavoriteSmileys()
    }

    private func performBBCode(_ tag: BBCodeTag, range: NSRange) {
        let result = ReplyTextInsertionEngine.wrapWithBBCode(tag, in: message, selectedUTF16Range: range)
        applyInsertionResult(result)
    }

    private func performSplitQuote(atUTF16Offset offset: Int) {
        guard let result = ReplyTextInsertionEngine.splitQuote(in: message, atUTF16Offset: offset) else { return }
        applyInsertionResult(result)
    }

    private func applyInsertionResult(_ result: ReplyTextInsertionResult) {
        message = result.text
        selectedRangeUTF16 = NSRange(location: result.cursorLocationUTF16, length: 0)
        requestEditorFocus()
    }

    private func clearComposer() {
        message = ""
        selectedRangeUTF16 = NSRange(location: 0, length: 0)
        requestEditorFocus()
    }

    private func performUndo() {
        guard !undoHistory.isEmpty else { return }
        let current = message
        let previous = undoHistory.removeLast()
        pendingHistoryMutationsToSkip += 1
        redoHistory.append(current)
        message = previous
        selectedRangeUTF16 = NSRange(location: previous.utf16.count, length: 0)
        requestEditorFocus()
    }

    private func performRedo() {
        guard !redoHistory.isEmpty else { return }
        let current = message
        let next = redoHistory.removeLast()
        pendingHistoryMutationsToSkip += 1
        undoHistory.append(current)
        message = next
        selectedRangeUTF16 = NSRange(location: next.utf16.count, length: 0)
        requestEditorFocus()
    }

    private func dismissComposer() {
        if isComposerPresented { isComposerPresented = false }
        dismiss()
    }

    private func enforceSubjectCharacterLimit(_ value: String) {
        guard let limit = effectiveSubjectCharacterLimit, value.count > limit else { return }
        composerSubject = String(value.prefix(limit))
    }

    // MARK: Network

    private func loadComposerContext() async {
        guard let topicURL else { return }
        if let loader = replyPostingService as? any ReplyComposerContextLoading,
           let context = try? await loader.fetchComposerContext(topicURL: topicURL) {
            await MainActor.run {
                if composerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let subject = context.subject { composerSubject = subject }
                if composerRecipient == nil, let recipient = context.recipient {
                    composerRecipient = recipient
                }
                contextShowsSubjectField = context.isSubjectEditable
                contextShowsSubcategoryPicker = context.isSubcategoryEditable
                subcategoryOptions = context.subcategoryOptions
                if selectedSubcategoryID == nil {
                    selectedSubcategoryID = context.selectedSubcategoryID ?? context.subcategoryOptions.first?.id
                }
                enforceSubjectCharacterLimit(composerSubject)
            }
        } else if let preloader = replyPostingService as? any ReplyComposerContextPreloading {
            await preloader.preloadReplyContext(topicURL: topicURL)
        }
        await MainActor.run {
            reloadFavoriteSmileys()
        }
    }

    private func startImageUpload(with image: UIImage) {
        imageUploadTask?.cancel()
        isImageUploading = true
        imageUploadError = nil
        let maxDimension = imageUploadPreferences.maxDimension
        imageUploadTask = Task {
            do {
                let uploaded = try await imageUploadService.uploadImage(image, maxDimension: maxDimension)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    uploadedImages.insert(uploaded, at: 0)
                    isImageUploading = false
                    imageUploadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { isImageUploading = false; imageUploadTask = nil }
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

    private func postMessage() async {
        guard !isPosting else { return }
        guard let topicURL else {
            triggerPostHaptic(success: false)
            presentToast(success: false, text: "URL manquante")
            return
        }
        isPosting = true
        defer { isPosting = false }
        do {
            var overrides: [String: String] = [:]
            if showsSubjectField {
                overrides["sujet"] = composerSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if showsSubcategoryPicker, let selectedSubcategoryID {
                overrides["subcat"] = selectedSubcategoryID
            }
            if let recipient = composerRecipient { overrides["dest"] = recipient }

            let result = try await replyPostingService.postReply(
                message: message,
                topicURL: topicURL,
                formOverrides: overrides
            )
            await MainActor.run { onPostSuccess?(result) }
            triggerPostHaptic(success: true)
            presentToast(success: true, text: "Hooray")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                message = ""
                undoHistory.removeAll()
                redoHistory.removeAll()
                pendingHistoryMutationsToSkip = 0
                composerDraftText = ComposerDraftPersistence.draftAfterSuccessfulPost(
                    existingDraft: composerDraftText,
                    persistsDraft: persistsComposerDraft
                )
                composerSubject = ""
                selectedSubcategoryID = nil
                dismissComposer()
            }
        } catch let error as ReplyPostingError {
            triggerPostHaptic(success: false)
            presentToast(success: false, text: error.localizedDescription)
        } catch {
            triggerPostHaptic(success: false)
            presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
    }

    // MARK: Haptics

    private func triggerPostHaptic(success: Bool) {
        guard AppHaptics.isEnabled else { return }
        AppHaptics.notification(success ? .success : .error)
        AppHaptics.impact(success ? .light : .rigid)
    }

    private func updateFavoriteSmiley(_ smiley: ReplySmiley, add: Bool) -> Bool {
        guard case .remote(let imageURL) = smiley.imageSource else {
            presentToast(success: false, text: "Smiley non compatible")
            return false
        }

        let didUpdate = ReplySmileyCacheBridge.updateAppFavorite(
            code: smiley.code,
            imageURL: imageURL.absoluteString,
            add: add
        )
        guard didUpdate else {
            presentToast(success: false, text: "Erreur :/")
            return false
        }

        reloadFavoriteSmileys()
        AppHaptics.impact(.light)
        presentToast(
            success: true,
            text: add ? "Smiley ajouté aux favoris" : "Smiley retiré des favoris"
        )
        return true
    }

    private func fetchSmileyKeywords(code: String) async -> Result<[String], Error> {
        let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        guard let url = URL(string: "https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=\(encodedCode)") else {
            return .failure(
                NSError(
                    domain: "AnswerView",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "URL invalide."]
                )
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    NSError(
                        domain: "AnswerView",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse serveur invalide."]
                    )
                )
            }

            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return .failure(
                    NSError(
                        domain: "AnswerView",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse illisible."]
                    )
                )
            }

            let pattern = #"name\s*=\s*"keywords0"[^>]*value\s*=\s*"([^"]*)""#
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..<html.endIndex, in: html)),
                match.numberOfRanges > 1,
                let valueRange = Range(match.range(at: 1), in: html)
            else {
                return .failure(
                    NSError(
                        domain: "AnswerView",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Aucun mot clé trouvé."]
                    )
                )
            }

            let rawValue = String(html[valueRange])
            let decodedEntities = rawValue
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&#x2F;", with: "/")
                .replacingOccurrences(of: "&#47;", with: "/")

            let keywords = decodedEntities
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }

            if keywords.isEmpty {
                return .failure(
                    NSError(
                        domain: "AnswerView",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Aucun mot clé trouvé."]
                    )
                )
            }
            return .success(keywords)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Toast

    private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Toolbar components

private struct ComposerToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        } else {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemBackground), in: .capsule)
                .overlay { Capsule().stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 1) }
        }
    }
}

private struct ComposerToolbarButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isDisabled: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 18, height: 18)
                .padding(8)
                .foregroundStyle(isDestructive ? .red : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - View modifiers

private extension View {
    @ViewBuilder
    func composerCloseButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonBorderShape(.circle).buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).clipShape(.circle)
        }
    }

    @ViewBuilder
    func composerSendButtonStyle(isEnabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isEnabled {
                self.buttonBorderShape(.circle).buttonStyle(.glassProminent)
            } else {
                self.buttonBorderShape(.circle).buttonStyle(.glass)
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

    @ViewBuilder
    func smileySearchButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonBorderShape(.circle).buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).clipShape(.circle)
        }
    }

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
                self.tint(tint).buttonStyle(.borderedProminent)
            } else {
                self.tint(tint).buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Sheet close header (shared by all panels)

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

// MARK: - Smiley picker (with favorites and search)
//
// Presented as a sheet — UIKit handles keyboard transitions naturally on present/dismiss.
// No manual focus timing needed.

private enum SmileyPickerDisplayMode: Equatable {
    case library
    case results
    case empty
}

private struct SmileyPickerSessionState: Equatable {
    var displayMode: SmileyPickerDisplayMode = .library
    var searchResults: [ReplySmiley] = []
    var searchText = ""
}

private struct CombinedSmileyPickerView: View {
    let defaultSmileys: [ReplySmiley]
    let forumFavoriteSmileys: [ReplySmiley]
    let appFavoriteSmileys: [ReplySmiley]
    @Binding var sessionState: SmileyPickerSessionState
    let onSelect: (ReplySmiley) -> Void
    let onToggleFavorite: (ReplySmiley, Bool) -> Bool
    let onFetchKeywords: (String) async -> Result<[String], Error>

    @Environment(\.dismiss) private var dismiss
    @AppStorage("AnswerView.smileys.basic.expanded") private var isBasicSectionExpanded = true
    @AppStorage("AnswerView.smileys.forumFavorites.expanded") private var isForumFavoritesSectionExpanded = true
    @AppStorage("AnswerView.smileys.appFavorites.expanded") private var isAppFavoritesSectionExpanded = true
    private let defaultColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let favoriteColumns = [GridItem(.adaptive(minimum: 78, maximum: 90), spacing: 4)]
    private let searchService: any SmileySearching = HFRSmileySearchService()

    @State private var isSearching = false
    @State private var recentSuggestions: [SmileySearchHistoryEntry] = []
    @State private var topSuggestions: [SmileySearchHistoryEntry] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var presentedSmiley: ReplySmiley?
    @FocusState private var isSearchFieldFocused: Bool

    private var displayedSmileys: [ReplySmiley] {
        if sessionState.displayMode == .results { return sessionState.searchResults }
        return []
    }
    private var isShowingResults: Bool {
        if case .library = sessionState.displayMode { return false }
        return true
    }
    private var canSearch: Bool { sessionState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
    private var showSuggestions: Bool {
        (!recentSuggestions.isEmpty || !topSuggestions.isEmpty) && sessionState.displayMode == .library
    }
    private var suggestionChips: [SmileySearchHistoryEntry] {
        if sessionState.searchText.isEmpty { return Array(recentSuggestions.prefix(4)) }
        let recentTexts = Set(recentSuggestions.map { $0.text })
        let uniqueTop = topSuggestions.filter { !recentTexts.contains($0.text) }
        return Array((recentSuggestions + uniqueTop).prefix(5))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ComposerSheetCloseHeader(title: "Smileys") { dismiss() }

                ScrollView {
                    if case .empty = sessionState.displayMode {
                        emptyState
                    } else if isShowingResults {
                        smileyGrid(displayedSmileys, columns: favoriteColumns, isCompact: false)
                            .padding(8)
                    } else {
                        smileyLibrary
                    }
                }

                if showSuggestions && !suggestionChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestionChips) { entry in
                                Button {
                                    search(using: entry.text)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: sessionState.searchText.isEmpty ? "clock" : "magnifyingglass")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(entry.text).font(.subheadline)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .smileyChipStyle()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }

                Divider()
                searchBarRow
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .allowsHitTesting(presentedSmiley == nil)

            if let presentedSmiley {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.presentedSmiley = nil
                    }

                FavoriteSmileyDetailView(
                    smiley: presentedSmiley,
                    initiallyFavorite: ReplySmileyCacheBridge.isFavoriteFromApp(code: presentedSmiley.code),
                    allowsFavoriteToggle: !isFavoriteLibrarySmiley(presentedSmiley),
                    onInsert: {
                        isSearchFieldFocused = false
                        onSelect(presentedSmiley)
                        dismiss()
                    },
                    onToggleFavorite: { add in
                        onToggleFavorite(presentedSmiley, add)
                    },
                    onFetchKeywords: {
                        await onFetchKeywords(presentedSmiley.code)
                    },
                    onSearchKeyword: { keyword in
                        self.presentedSmiley = nil
                        search(using: keyword)
                    },
                    onClose: {
                        self.presentedSmiley = nil
                    }
                )
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationGlassBackground()
        .animation(.easeInOut(duration: 0.18), value: presentedSmiley?.id)
        .onAppear { refreshSuggestions() }
        .onChange(of: sessionState.searchText) { _, _ in refreshSuggestions() }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: Search bar

    private var searchBarRow: some View {
        HStack(spacing: 8) {
            if isShowingResults {
                Button(action: clearSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(8)
                }
                .accessibilityLabel("Retour aux smileys")
                .smileySearchButtonStyle()
            }

            HStack {
                TextField("Rechercher un smiley…", text: $sessionState.searchText)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { performSearch() }

                if !sessionState.searchText.isEmpty {
                    Button {
                        sessionState.searchText = ""
                        refreshSuggestions()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .smileySearchFieldStyle()

            if isSearching {
                ProgressView().controlSize(.small).frame(width: 36, height: 36)
            } else {
                Button(action: { performSearch() }) {
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

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Aucun smiley trouvé").font(.headline).foregroundStyle(.secondary)
            Text("Essayez avec un autre mot-clé.").font(.subheadline).foregroundStyle(.tertiary)
            Button("Retour aux smileys", action: clearSearch)
                .font(.subheadline).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80).padding(.bottom, 20)
    }

    // MARK: Logic

    private func performSearch(queryOverride: String? = nil) {
        let query = (queryOverride ?? sessionState.searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        isSearchFieldFocused = false
        if sessionState.searchText != query {
            sessionState.searchText = query
        }
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            do {
                let results = try await searchService.search(query: query)
                guard !Task.isCancelled else { return }
                SmileySearchHistoryStore.record(query: query, resultCount: results.count)
                await MainActor.run {
                    isSearching = false
                    sessionState.searchResults = results
                    sessionState.displayMode = results.isEmpty ? .empty : .results
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSearching = false
                    sessionState.searchResults = []
                    sessionState.displayMode = .empty
                }
            }
        }
    }

    private func clearSearch() {
        isSearchFieldFocused = false
        searchTask?.cancel()
        isSearching = false
        sessionState.displayMode = .library
        sessionState.searchResults = []
    }

    private func search(using query: String) {
        presentedSmiley = nil
        performSearch(queryOverride: query)
    }

    private func refreshSuggestions() {
        recentSuggestions = SmileySearchHistoryStore.recentSuggestions(matching: sessionState.searchText)
        topSuggestions = SmileySearchHistoryStore.topSuggestions(matching: sessionState.searchText)
    }

    private func smileyItem(_ smiley: ReplySmiley) -> some View {
        Button {
            isSearchFieldFocused = false
            presentedSmiley = smiley
        } label: {
            SmileyGridCell(smiley: smiley, isCompact: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(smiley.code)
    }

    private var smileyLibrary: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            collapsibleSmileySection(
                title: "Smileys basiques",
                smileys: defaultSmileys,
                isExpanded: $isBasicSectionExpanded,
                columns: defaultColumns,
                isCompact: true,
                tapBehavior: .insertDirectly
            )

            collapsibleSmileySection(
                title: "Smileys du forum",
                smileys: forumFavoriteSmileys,
                isExpanded: $isForumFavoritesSectionExpanded,
                columns: favoriteColumns,
                isCompact: false,
                emptyText: "Aucun smiley forum disponible.",
                tapBehavior: .showDetails
            )

            collapsibleSmileySection(
                title: "Favoris de l'app",
                smileys: appFavoriteSmileys,
                isExpanded: $isAppFavoritesSectionExpanded,
                columns: favoriteColumns,
                isCompact: false,
                emptyText: "Aucun favori dans l'app pour le moment.",
                tapBehavior: .showDetails
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private enum SmileyTapBehavior {
        case insertDirectly
        case showDetails
    }

    private func collapsibleSmileySection(
        title: String,
        smileys: [ReplySmiley],
        isExpanded: Binding<Bool>,
        columns: [GridItem],
        isCompact: Bool,
        emptyText: String? = nil,
        tapBehavior: SmileyTapBehavior
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(smileys.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                if smileys.isEmpty, let emptyText {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                } else {
                    smileyGrid(smileys, columns: columns, isCompact: isCompact, tapBehavior: tapBehavior)
                }
            }
        }
    }

    private func isFavoriteLibrarySmiley(_ smiley: ReplySmiley) -> Bool {
        forumFavoriteSmileys.contains(smiley) || appFavoriteSmileys.contains(smiley)
    }

    private func smileyGrid(
        _ smileys: [ReplySmiley],
        columns: [GridItem],
        isCompact: Bool,
        tapBehavior: SmileyTapBehavior = .showDetails
    ) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(smileys) { smiley in
                Button {
                    isSearchFieldFocused = false
                    switch tapBehavior {
                    case .insertDirectly:
                        onSelect(smiley)
                        dismiss()
                    case .showDetails:
                        presentedSmiley = smiley
                    }
                } label: {
                    SmileyGridCell(smiley: smiley, isCompact: isCompact)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(smiley.code)
            }
        }
    }
}

private struct FavoriteSmileyDetailView: View {
    let smiley: ReplySmiley
    let initiallyFavorite: Bool
    let allowsFavoriteToggle: Bool
    let onInsert: () -> Void
    let onToggleFavorite: (Bool) -> Bool
    let onFetchKeywords: () async -> Result<[String], Error>
    let onSearchKeyword: (String) -> Void
    let onClose: () -> Void

    @Environment(\.appThemePalette) private var themePalette
    @State private var isFavorite: Bool
    @State private var keywords: [String] = []
    @State private var isLoadingKeywords = false
    @State private var keywordsErrorMessage: String?

    init(
        smiley: ReplySmiley,
        initiallyFavorite: Bool,
        allowsFavoriteToggle: Bool = true,
        onInsert: @escaping () -> Void,
        onToggleFavorite: @escaping (Bool) -> Bool,
        onFetchKeywords: @escaping () async -> Result<[String], Error>,
        onSearchKeyword: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.smiley = smiley
        self.initiallyFavorite = initiallyFavorite
        self.allowsFavoriteToggle = allowsFavoriteToggle
        self.onInsert = onInsert
        self.onToggleFavorite = onToggleFavorite
        self.onFetchKeywords = onFetchKeywords
        self.onSearchKeyword = onSearchKeyword
        self.onClose = onClose
        _isFavorite = State(initialValue: initiallyFavorite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.secondary)
                        .background(themePalette.controlBackgroundColor.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }

            VStack(spacing: 12) {
                SmileyPreviewView(smiley: smiley)
                    .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132)
                    .background(themePalette.tertiaryBackgroundColor, in: .rect(cornerRadius: 14))

                Text(smiley.code)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                Button(action: onInsert) {
                    Label("Insérer", systemImage: "text.insert")
                        .frame(maxWidth: .infinity)
                }
                .replyTintedActionButtonStyle(useProminent: true, tint: .accentColor)

                Button {
                    let add = !isFavorite
                    guard onToggleFavorite(add) else { return }
                    isFavorite.toggle()
                } label: {
                    Label(
                        isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                    .frame(maxWidth: .infinity)
                }
                .replyTintedActionButtonStyle(useProminent: false, tint: .accentColor)
                .disabled(!allowsFavoriteToggle)
                .opacity(allowsFavoriteToggle ? 1 : 0.45)
            }

            if isLoadingKeywords || !keywords.isEmpty || keywordsErrorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mots clés")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if isLoadingKeywords {
                        ProgressView("Chargement des mots clés…")
                            .font(.footnote)
                    } else if !keywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(keywords, id: \.self) { keyword in
                                    Button(keyword) {
                                        onSearchKeyword(keyword)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .smileyChipStyle()
                                }
                            }
                        }
                    } else if let keywordsErrorMessage {
                        Text(keywordsErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(themePalette.controlBackgroundColor.opacity(0.7), in: .rect(cornerRadius: 12))
            }
        }
        .padding(14)
        .frame(maxWidth: 340)
        .background(detailBackground)
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .task {
            isLoadingKeywords = true
            keywordsErrorMessage = nil
            switch await onFetchKeywords() {
            case .success(let fetchedKeywords):
                keywords = fetchedKeywords
            case .failure(let error):
                keywords = []
                keywordsErrorMessage = error.localizedDescription
            }
            isLoadingKeywords = false
        }
    }

    @ViewBuilder
    private var detailBackground: some View {
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(in: .rect(cornerRadius: 24))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Smiley grid cell

private struct SmileyGridCell: View {
    let smiley: ReplySmiley
    var isCompact = false
    @Environment(\.appThemePalette) private var themePalette

    var body: some View {
        SmileyThumbnailView(smiley: smiley)
            .frame(width: isCompact ? 40 : 70, height: isCompact ? 32 : 50)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 40 : 58)
            .background(themePalette.tertiaryBackgroundColor)
            .clipShape(.rect(cornerRadius: isCompact ? 7 : 8))
            .contentShape(Rectangle())
    }
}

// MARK: - Smiley thumbnail (animated GIF)

private struct SmileyThumbnailView: UIViewRepresentable {
    let smiley: ReplySmiley
    var contentMode: UIView.ContentMode = .center

    func makeUIView(context: Context) -> UIImageView {
        let imageView: UIImageView
        if let animatedClass = NSClassFromString("SDAnimatedImageView") as? NSObject.Type,
           let animatedView = animatedClass.init() as? UIImageView {
            imageView = animatedView
        } else {
            imageView = UIImageView()
        }
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.update(uiView, with: smiley)
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        coordinator.cancelPendingWork()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private static let bundledCache = NSCache<NSString, UIImage>()
        private static let remoteCache = NSCache<NSString, UIImage>()
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
                let key = url.absoluteString as NSString
                if let cached = Self.remoteCache.object(forKey: key) {
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
            if let cached = Self.bundledCache.object(forKey: key) { return cached }
            let nsFilename = filename as NSString
            let baseName = nsFilename.deletingPathExtension
            let ext = nsFilename.pathExtension.isEmpty ? "gif" : nsFilename.pathExtension
            let bundle = Bundle.main
            guard let path = bundle.path(forResource: baseName, ofType: ext)
                    ?? bundle.path(forResource: baseName, ofType: ext, inDirectory: "Assets/HFR/Smilies"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = decodeGIFImage(from: data) else { return nil }
            Self.bundledCache.setObject(image, forKey: key)
            return image
        }

        private func loadRemoteGIF(from url: URL) async -> UIImage? {
            let key = url.absoluteString as NSString
            if let cached = Self.remoteCache.object(forKey: key) { return cached }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = decodeGIFImage(from: data) else { return nil }
            Self.remoteCache.setObject(image, forKey: key)
            return image
        }

        private func decodeGIFImage(from data: Data) -> UIImage? {
            // Priority: SDWebImage's sd_animatedGIFWithData: for proper animated image support.
            let selector = NSSelectorFromString("sd_animatedGIFWithData:")
            let imageClass: AnyObject = UIImage.self
            if imageClass.responds(to: selector),
               let unmanaged = imageClass.perform(selector, with: data),
               let image = unmanaged.takeUnretainedValue() as? UIImage {
                return image
            }
            // Fallback: CGImageSource multi-frame decode.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 1 else { return UIImage(data: data) }
            var frames: [UIImage] = []
            var totalDuration = 0.0
            for index in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                totalDuration += Self.frameDuration(at: index, in: source)
                // Scale 1.0 preserves the GIF's natural pixel size.
                frames.append(UIImage(cgImage: cgImage, scale: 1.0, orientation: .up))
            }
            guard !frames.isEmpty else { return UIImage(data: data) }
            if totalDuration <= 0 { totalDuration = Double(frames.count) * 0.1 }
            return UIImage.animatedImage(with: frames, duration: totalDuration)
        }

        private static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else { return 0.1 }
            let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double
            let duration = unclamped ?? clamped ?? 0.1
            return duration < 0.011 ? 0.1 : duration
        }
    }
}

private struct SmileyPreviewView: View {
    let smiley: ReplySmiley

    var body: some View {
        SmileyThumbnailView(smiley: smiley, contentMode: .scaleAspectFit)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
    }
}

// MARK: - Image insertion panel

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

    private var canUseCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var canInsertManualURL: Bool {
        let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    private var prefersProminentPrimaryButtons: Bool { themePalette.colorScheme == .light }
    private var secondaryControlTintColor: Color {
        themePalette.colorScheme == .light ? Color(uiColor: .systemGray3) : themePalette.actionTintColor
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposerSheetCloseHeader(title: "Insérer image") { dismiss() }

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
                        Text("Dimension maximale").font(.caption).foregroundStyle(.secondary)
                        Picker("Dimension maximale", selection: $preferences.maxDimension) {
                            ForEach(RehostUploadMaxDimension.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(secondaryControlTintColor)
                    }

                    if isUploading { ProgressView("Upload en cours...") }
                    if let err = uploadError, !err.isEmpty {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Images uploadées") {
                    Picker("Type de bbcode", selection: $preferences.bbCodeMode) {
                        ForEach(RehostBBCodeMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .tint(secondaryControlTintColor)

                    if uploadedImages.isEmpty {
                        Text("Aucune image uploadée.").foregroundStyle(.secondary)
                    } else {
                        ForEach(uploadedImages) { image in
                            ReplyUploadedImageRow(
                                image: image,
                                mode: preferences.bbCodeMode,
                                onPreviewImage: { previewImage(image) }
                            ) { variant in
                                insertUploadedImage(image, variant: variant)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    uploadedImages.removeAll { $0.id == image.id }
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

                    Button("Insérer") { insertManualURL() }
                        .replyTintedActionButtonStyle(useProminent: false, tint: secondaryControlTintColor)
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
                    onCancel: { presentedPicker = nil },
                    onPick: { image in presentedPicker = nil; onPickImage(image) }
                ).ignoresSafeArea()
            case .camera:
                ReplyUIKitImagePicker(
                    sourceType: .camera,
                    onCancel: { presentedPicker = nil },
                    onPick: { image in presentedPicker = nil; onPickImage(image) }
                ).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $photoViewerDestination) { dest in
            FullScreenPhotoViewer(url: dest.url, presentationID: dest.id)
        }
        .presentationGlassBackground()
    }

    private func insertUploadedImage(_ image: RehostUploadedImage, variant: RehostImageSizeVariant) {
        guard let snippet = image.formattedSnippet(for: variant, mode: preferences.bbCodeMode) else { return }
        onInsertSnippet(snippet)
        dismiss()
    }

    private func previewImage(_ image: RehostUploadedImage) {
        for candidateString in [image.fullURL, image.mediumURL, image.previewURL, image.miniURL].compactMap({ $0 }) {
            if let url = URL(string: candidateString) {
                photoViewerDestination = ReplyPhotoViewerDestination(url: url)
                return
            }
        }
    }

    private func insertManualURL() {
        let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let manualImage = RehostUploadedImage(
            fullWidth: nil, fullHeight: nil, fullURL: trimmed,
            mediumURL: nil, previewURL: nil, miniURL: nil
        )
        guard let snippet = manualImage.formattedSnippet(for: .full, mode: preferences.bbCodeMode) else { return }
        onInsertSnippet(snippet)
        dismiss()
    }
}

// MARK: - Uploaded image row

private struct ReplyUploadedImageRow: View {
    let image: RehostUploadedImage
    let mode: RehostBBCodeMode
    let onPreviewImage: () -> Void
    let onInsertVariant: (RehostImageSizeVariant) -> Void
    @Environment(\.appThemePalette) private var themePalette

    private var secondaryControlTintColor: Color {
        themePalette.colorScheme == .light ? Color(uiColor: .systemGray3) : themePalette.actionTintColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onPreviewImage) {
                    AsyncImage(url: URL(string: image.thumbnailURL)) { phase in
                        switch phase {
                        case .success(let preview):
                            preview.resizable().scaledToFill()
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
                    Text(mode.title).font(.caption).foregroundStyle(.secondary)
                    Text(image.maxDimensionText ?? "Image").font(.footnote).foregroundStyle(.primary)
                    Text(image.fullURL).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                ForEach(image.availableVariants) { variant in
                    Button { onInsertVariant(variant) } label: {
                        Text(variant.title).frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .replyTintedActionButtonStyle(useProminent: false, tint: secondaryControlTintColor)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Picker helpers

private enum ReplyPresentedImagePicker: String, Identifiable {
    case photoLibrary, camera
    var id: String { rawValue }
}

private struct ReplyPhotoViewerDestination: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - UIImagePickerController wrapper (camera)

private struct ReplyUIKitImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCancel: onCancel, onPick: onPick) }

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
            self.onCancel = onCancel; self.onPick = onPick
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [onCancel] in onCancel() }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true) { [onCancel] in onCancel() }
                return
            }
            picker.dismiss(animated: true) { [onPick] in onPick(image) }
        }
    }
}

// MARK: - PHPickerViewController wrapper

private struct ReplyPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCancel: onCancel, onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onCancel: () -> Void
        private let onPick: (UIImage) -> Void

        init(onCancel: @escaping () -> Void, onPick: @escaping (UIImage) -> Void) {
            self.onCancel = onCancel; self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                picker.dismiss(animated: true) { [onCancel] in onCancel() }
                return
            }
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                picker.dismiss(animated: true) { [onCancel] in onCancel() }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [onPick, onCancel] object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        picker.dismiss(animated: true) { onPick(image) }
                    } else {
                        picker.dismiss(animated: true) { onCancel() }
                    }
                }
            }
        }
    }
}

// MARK: - UITextView wrapper
//
// Design rationale for focus:
// - becomeFirstResponder is called ONLY when focusRequest.consume() returns true.
// - focusTrigger (an Int in the parent) drives the SwiftUI re-render that causes
//   updateUIView to run at the right moment.
// - resignFirstResponder is never called manually — UIKit handles it automatically
//   when a sheet is presented over the editor.
// - The Coordinator does NOT write back to an isFocused binding, which was the
//   root cause of the re-render loops in the previous implementation.

private struct ReplyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let focusRequest: TextEditorFocusRequest
    let focusTrigger: Int   // changing this forces updateUIView to be called
    let textSizeScaleRawValue: Int
    var onBBCodeAction: ((BBCodeTag, NSRange) -> Void)?
    var onSplitQuote: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var editorFont: UIFont {
        AppTextSizeScale.scaledUIFont(
            textStyle: .body,
            basePointSize: 17,
            rawValue: textSizeScaleRawValue
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = editorFont
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocapitalizationType = .sentences
        tv.autocorrectionType = .yes
        tv.keyboardDismissMode = .none
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        uiView.font = editorFont

        if uiView.text != text {
            uiView.text = text
        }

        let clamped = clampedRange(selectedRange, utf16Count: uiView.text.utf16.count)
        if uiView.selectedRange != clamped {
            uiView.selectedRange = clamped
        }

        // Consume a pending focus request. becomeFirstResponder is called only when
        // explicitly requested — not on every render — so no re-render loop occurs.
        if focusRequest.consume() {
            uiView.becomeFirstResponder()
        }
    }

    private func clampedRange(_ range: NSRange, utf16Count: Int) -> NSRange {
        let loc = max(0, min(range.location, utf16Count))
        let len = max(0, min(range.length, utf16Count - loc))
        return NSRange(location: loc, length: len)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReplyTextEditor

        init(_ parent: ReplyTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text { parent.text = textView.text }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }

        @available(iOS 16.0, *)
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            var children = suggestedActions

            // "Fractionner la citation" uniquement si pas de sélection
            if range.length == 0 {
                let cursorLocation = range.location
                let splitAction = UIAction(
                    title: "Fractionner la citation",
                    image: UIImage(systemName: "scissors")
                ) { [weak self] _ in
                    self?.parent.onSplitQuote?(cursorLocation)
                }
                children.append(splitAction)
            }

            // Actions BBCode
            for tag in BBCodeTag.allCases {
                let capturedRange = range
                let image = tag.systemImage.flatMap { UIImage(systemName: $0) }
                let action = UIAction(title: tag.label, image: image) { [weak self] _ in
                    self?.parent.onBBCodeAction?(tag, capturedRange)
                }
                children.append(action)
            }

            return UIMenu(title: "", options: .displayInline, children: children)
        }
    }
}

// MARK: - Toast

// MARK: - Giphy panel
//
// GiphyViewController manages its own card-style presentation internally.
// We use a transparent container VC and let Giphy present itself on it,
// exactly like the legacy ObjC code does with [self presentViewController:...].
// This avoids the half-height layout issue caused by embedding Giphy inside a
// SwiftUI fullScreenCover view hierarchy.

private struct GiphyPanel: UIViewControllerRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .clear

        let giphy = GiphyViewController()
        giphy.delegate = context.coordinator
        giphy.theme = GPHTheme(type: colorScheme == .dark ? .darkBlur : .light)
        giphy.rating = .ratedR
        giphy.showConfirmationScreen = true
        giphy.mediaTypeConfig = [.gifs, .recents]

        context.coordinator.giphyViewController = giphy

        // Present after the container is in the hierarchy
        DispatchQueue.main.async {
            container.present(giphy, animated: true)
        }
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, GiphyDelegate {
        let onSelect: (String) -> Void
        let onDismiss: () -> Void
        weak var giphyViewController: GiphyViewController?

        init(onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onDismiss = onDismiss
        }

        func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia) {
            guard let url = media.images?.original?.gifUrl else { return }
            onSelect("[img]\(url)[/img]\n")
            onDismiss()
        }

        func didDismiss(controller: GiphyViewController?) {
            onDismiss()
        }
    }
}

// MARK: - Toast

private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? Color.primary : Color.orange)
                .font(.headline)
            Text(text).font(.headline).foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hfrToastSurface()
    }
}

// MARK: - Preview

private struct AnswerViewPreviewWrapper: View {
    @State private var draft = ""
    @State private var presented = false

    var body: some View {
        NavigationStack {
            AnswerView(
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1#t100")!,
                initialMessage: draft,
                composerDraftText: $draft,
                isComposerPresented: $presented
            )
        }
    }
}

#Preview { AnswerViewPreviewWrapper() }
