import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (AnswerView, reply mode; new topic: sub-category `Picker`, :395-420, GAP-098; edit mode, GAP-096)
// @ 2440d79.
// Differences: formatting toolbar (LOT-085, GAP-085); image panel (LOT-102, GAP-090),
// GIF panel (`GifPanel`, LOT-155, GAP-089), smiley picker as a sheet from the toolbar (LOT-104, GAP-087);
// errors say whether anything was posted instead of the toast (GAP-100); draft per topic (GAP-092, UXD); the formatting bar is
// pinned to the keyboard safe area and off while the recipient or subject has focus (#599, GAP-085).
// Layout of HFRswift/Swift/AnswerView.swift (composerHeader `:768-819`, composerToolbar `:940-962`) @ 87fe0d1c: close `xmark` on the
// left, send `arrow.up` on the right, the control row and the "Aa" bar above the keyboard (#653, `ComposerControlRow`). Differences:
// every composer opens at partial height on an iPhone, the page visible above and scrollable, its taps ignored (`ComposerHeight`,
// GAP-653, b·operator); no drafts button here (LOT-101, #192, plans one for the new-topic composer).
/// The composer sheet: a plain text editor, close and Send; a new topic adds its subject and sub-category (LOT-089); a new
/// private message adds its recipient and subject
/// (LOT-128, legacy "À :" field, `QuoteMessageViewController.m:306-330` @ 21173e77). Thin: every rule is in
/// `ReplyComposerModel`.
///
/// The editor is SwiftUI's own `TextEditor` with the system keyboard type, so third-party keyboards work (legacy backlog
/// HFR-001) and the text is never rewritten under the cursor; the sheet's keyboard safe area keeps the caret visible.
struct ReplyComposerView: View {
    let model: ReplyComposerModel
    /// The presenter ignores its page's taps while this sheet is open: at partial height the page above stays scrollable (#653).
    let pageScrolls: Bool
    /// Called once with the reason, right before the sheet goes away.
    let onClose: (ReplyComposerModel.CloseReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Field?
    @State private var selection: TextSelection?
    /// The first focus (once the draft is read) happened: later `canEdit` flips (a send) never steal it.
    @State private var didFocus = false
    @State private var picker: SmileyPickerModel?
    /// The smiley search outlives the panel, as legacy's session state: reopening shows the last results (LOT-105).
    @State private var smileySearch: SmileySearchModel?
    /// A smiley was inserted by the open picker: focus goes back to the editor when it closes, not after a plain "Fermer".
    @State private var smileyInserted = false
    /// The editor's selection when the picker opened: the sheet takes focus, so the live binding is not trusted.
    @State private var rangeForSmiley: Range<String.Index>?

    private typealias Field = ComposerField

    @State private var formatting: ComposerFormattingModel
    /// Lives as long as the composer, so an upload finishing after the panel closed still lands in the list.
    @State private var imageUpload: ImageUploadModel
    @State private var isShowingImages = false
    /// A snippet was inserted by the closed panel: focus goes back to the editor.
    @State private var imageInserted = false
    /// The caret when "Image" was tapped: the sheet takes focus, so the live selection is not trusted (as for smileys).
    @State private var rangeImage = NSRange(location: 0, length: 0)
    /// "GIF Giphy" was tapped: `gifPanel` opens its sheet.
    @State private var gifRequested = false
    /// The height chosen with the toggle; nil until then (partial on an iPhone). Not remembered: every opening starts partial.
    @State private var chosenHeight: ComposerHeight?

    init(model: ReplyComposerModel, pageScrolls: Bool = false, onClose: @escaping (ReplyComposerModel.CloseReason) -> Void) {
        self.model = model
        self.pageScrolls = pageScrolls
        self.onClose = onClose
        _formatting = State(initialValue: ComposerFormattingModel(composer: model, clipboard: SystemClipboard()))
        _imageUpload = State(initialValue: ImageUploadModel(services: model.imageUploadServices))
    }

    var body: some View {
        ThemedNavigationStack {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ComposerBanner(text: message, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        if model.mayHavePosted {
                            Button(checkTitle) { Task { await model.checkTopic() } }
                        }
                    }
                }
                if let warning = model.draftWarning {
                    ComposerBanner(text: warning, symbol: "externaldrive.badge.exclamationmark", tint: .secondary) {
                        // Keep and discard cannot close while the store refuses writes: the only exit, as the warning says.
                        if model.canCloseWithoutSaving {
                            Button("Fermer sans enregistrer", role: .destructive) { Task { await model.closeWithoutSaving() } }
                        }
                    }
                }
                if model.hasSubjectField { messageFields }
                editor
            }
            // Pinned to the bottom of the keyboard safe area as one view kept across focus changes, not a stack child laid
            // out with the fields (#599). Not `.keyboard` placement: that is an input accessory rebuilt for each focused
            // field (recipient, subject, text), shown above all three, and gone without an on-screen keyboard.
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .gifPanel(services: model.gifServices, formatting: formatting, request: $gifRequested) { focused = .text }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Utiliser le presse-papiers ?", isPresented: askingClipboard, presenting: formatting.pending) { pending in
                clipboardButtons(pending)
            } message: { pending in
                Text(pending.message)
            }
            .confirmationDialog("Garder ce texte ?", isPresented: askingClose, titleVisibility: .visible) {
                Button("Garder le brouillon") { Task { await model.keepDraftAndClose() } }
                Button("Supprimer le brouillon", role: .destructive) { Task { await model.discardDraftAndClose() } }
                Button("Continuer la saisie", role: .cancel) {}
            } message: {
                Text(keepDraftNote)
            }
        }
        .sheet(item: $picker, onDismiss: { if smileyInserted { focused = .text } }, content: { picker in
            SmileyPickerView(model: picker) { insertSmiley($0) }
        })
        .imageUploadSheet(
            isPresented: $isShowingImages, model: imageUpload,
            onDismiss: { if imageInserted { focused = .text } },
            onInsert: { formatting.selectedRange = rangeImage; formatting.insert($0); imageInserted = true }
        )
        .presentationDetents([height.detent(fieldRows: fieldRows)])
        .modifier(PartialComposerSheet(isEnabled: isPhone, height: height, fieldRows: fieldRows, pageScrolls: pageScrolls))
        // Swiping down would close without the choice: blocked while there is text or a send runs.
        .interactiveDismissDisabled(model.closeNeedsChoice || model.isSending)
        .task {
            await model.start()
            formatting.placeCaretAtEnd()
        }
        // The fields are disabled until the draft is read: focus set in the same task as `start()` lands on a disabled field
        // and is lost, so it waits for the view to enable them.
        .onChange(of: model.canEdit) { _, canEdit in
            guard canEdit, !didFocus else { return }
            didFocus = true
            focused = firstEmptyField
        }
        .task { await model.loadSubcategories() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.flushDraft() } }
        }
        .onChange(of: model.closeReason) { _, reason in
            guard let reason else { return }
            onClose(reason)
            dismiss()
        }
        .onDisappear {
            // Closed without a choice (account switch rebuilt the screens): keep what was typed.
            Task { await model.flushDraft() }
        }
    }

    private var askingClose: Binding<Bool> {
        Binding(get: { model.isAskingClose }, set: { model.isAskingClose = $0 })
    }

    private var askingClipboard: Binding<Bool> {
        Binding(
            get: { formatting.pending != nil },
            set: { if !$0 { formatting.dismissPending(); focused = .text } }
        )
    }

    /// The selected range of the editor, nil without a selection or with several (multi-selection is not used here).
    private var selectedRange: Range<String.Index>? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        return range
    }

    private func openSmileys() {
        let services = model.smileyServices
        smileySearch = smileySearch ?? services.search
        rangeForSmiley = selectedRange
        smileyInserted = false
        let catalogue = SmileyPickerModel.bundledCatalogue()
        picker = services.picker(catalogue: catalogue, search: smileySearch)
    }

    private func insertSmiley(_ code: String) {
        guard let caret = model.insert(smiley: code, replacing: rangeForSmiley) else { return }
        smileyInserted = true
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: caret, in: model.text))
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.text }, set: { model.update(text: $0) }), selection: $selection)
            .focused($focused, equals: .text)
            .scaledFont(.body)
            .disabled(!model.canEdit)
            .padding(.horizontal, 12)
            .overlay {
                if model.isRestoring { ProgressView() }
            }
            .accessibilityLabel(model.isNewMessage || model.isNewTopic || model.isEdit ? "Texte du message" : "Texte de la réponse")
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                formatting.selectedRange = Self.range(of: newValue, in: model.text)
            }
            .onChange(of: formatting.cursorRevision) {
                // The edit already changed the text: place the caret where the engine says, never at the end.
                let text = model.text
                let offset = min(formatting.selectedRange.location, text.utf16.count)
                // Focus is not taken here: `start()` places the caret too, and a new message opens on its recipient field.
                selection = TextSelection(insertionPoint: String.Index(utf16Offset: offset, in: text))
            }
    }

    private static func end(of text: String) -> NSRange { NSRange(location: text.utf16.count, length: 0) }

    /// The first selected range as a UTF-16 `NSRange`.
    private static func range(of selection: TextSelection, in text: String) -> NSRange {
        switch selection.indices {
        case .selection(let range) where range.upperBound <= text.endIndex: NSRange(range, in: text)
        case .multiSelection(let set):
            // A stale index (the text changed meanwhile) falls back to the end instead of trapping.
            if let first = set.ranges.first, first.upperBound <= text.endIndex { NSRange(first, in: text) } else { end(of: text) }
        default: end(of: text)
        }
    }

    /// Recipient (private message) or sub-category (topic) and subject, one line each, like HFR's own forms (`R45a`, `R45b`).
    private var messageFields: some View {
        VStack(spacing: 0) {
            if model.isNewMessage {
                TextField("Destinataire", text: Binding(get: { model.recipient }, set: { model.update(recipient: $0) }))
                    .focused($focused, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focused = .subject }
                    .accessibilityLabel("Pseudo du destinataire")
                    .padding(.vertical, 10)
                Divider()
            }
            if model.offersSubcategories, showsSubcategoryRow {
                subcategoryRow
                Divider()
            }
            TextField("Sujet", text: Binding(get: { model.subject }, set: { model.update(subject: $0) }))
                .focused($focused, equals: .subject)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.vertical, 10)
            Divider()
        }
        .scaledFont(.body)
        .disabled(!model.canEdit)
        .padding(.horizontal, 16)
    }

    /// The row has something to show: loading, the options or a failed read (a form without the select shows nothing).
    private var showsSubcategoryRow: Bool {
        model.picker.isLoading || !model.picker.options.isEmpty || model.picker.warning != nil
    }

    /// The form's sub-categories as a menu (legacy `Picker`, `AnswerView.swift:411`); a failed read says so and offers a retry.
    @ViewBuilder
    private var subcategoryRow: some View {
        if model.picker.isLoading {
            HStack {
                Text("Sous-catégorie")
                Spacer()
                ProgressView().accessibilityLabel("Chargement des sous-catégories")
            }
            .padding(.vertical, 10)
        } else if !model.picker.options.isEmpty {
            Picker("Sous-catégorie", selection: Binding(
                get: { model.picker.selected ?? "" }, set: { model.select(subcategory: $0) }
            )) {
                ForEach(model.picker.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.canEdit)
            .padding(.vertical, 2)
        } else if let warning = model.picker.warning {
            VStack(alignment: .leading, spacing: 6) {
                Text(warning).scaledFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { Task { await model.retrySubcategories() } }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Close first, then the height toggle, as legacy's header (`xmark` leftmost); one group so the order holds.
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Fermer", systemImage: "xmark") { Task { await model.requestClose() } }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isSending)
            if offersHeightToggle {
                let isPartial = height == .partial
                Button(
                    isPartial ? "Plein écran" : "Réduire",
                    systemImage: isPartial ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
                ) {
                    chosenHeight = height.toggled
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSending {
                ProgressView().accessibilityLabel("Envoi en cours")
            } else {
                Button("Envoyer", systemImage: "arrow.up") { Task { await model.send() } }
                    .disabled(!model.canSend)
            }
        }
    }
}

extension ReplyComposerView {
    /// The error banner's button after a send that may have posted: where to look.
    private var checkTitle: String {
        model.isNewTopic ? "Voir les sujets" : model.isNewMessage ? "Voir les messages" : "Voir le sujet"
    }

    private var keepDraftNote: String {
        if model.isNewTopic { return "Le brouillon est retrouvé au prochain nouveau sujet dans ce forum." }
        if model.isEdit { return "Le brouillon est retrouvé à la prochaine modification de ce message." }
        return model.isNewMessage
            ? "Le brouillon est retrouvé au prochain message à ce destinataire."
            : "Le brouillon est retrouvé à la prochaine réponse dans ce sujet."
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// An iPhone in regular height: partial height first, and the toggle (#653).
    private var offersHeightToggle: Bool {
        ComposerHeight.offersToggle(isPhone: isPhone, verticalSizeClass: verticalSizeClass)
    }

    private var height: ComposerHeight {
        ComposerHeight.shown(
            chosen: chosenHeight, isPhone: isPhone, verticalSizeClass: verticalSizeClass, largeText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var fieldRows: Int {
        ComposerHeight.fieldRows(hasSubject: model.hasSubjectField, hasSecondField: model.isNewMessage || model.isNewTopic)
    }

    /// The "Aa" bar when shown, above the control row: one view kept across focus changes (#599).
    private var controls: some View {
        VStack(spacing: 0) {
            if formatting.isBarShown { formattingBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            ComposerControlRow(
                model: model, formatting: formatting, offersGif: model.gifServices.isAvailable,
                openSmileys: openSmileys, openGif: { gifRequested = true }, openImages: openImages,
                refocus: { focused = ComposerBarFocus.focus(afterBarActionFrom: focused) }
            )
        }
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: formatting.isBarShown)
    }

    /// Off while the recipient or subject has focus; a tap never takes focus from them (`ComposerBarFocus`, #599).
    private var formattingBar: some View {
        let allowsBar = ComposerBarFocus.allowsBar(focused: focused)
        // `.plain` buttons draw no disabled state: the bar dims itself, as `FormattingToolbar` does for `isEnabled`.
        return FormattingToolbar(model: formatting) { focused = ComposerBarFocus.focus(afterBarActionFrom: focused) }
            .disabled(!allowsBar)
            .opacity(allowsBar ? 1 : 0.4)
    }

    /// Where typing starts: the first field of a new private message still empty, else the text.
    private var firstEmptyField: Field {
        guard model.hasSubjectField else { return .text }
        if model.isNewMessage, model.recipient.isEmpty { return .recipient }
        return model.subject.isEmpty ? .subject : .text
    }

    private var title: String {
        model.isEdit ? "Edition" : model.isNewTopic ? "Nouveau sujet" : model.isNewMessage ? "Nouveau message" : "Répondre"
    }
}

extension ReplyComposerView {
    /// The buttons of the clipboard alert, by what the tap could use.
    @ViewBuilder
    fileprivate func clipboardButtons(_ pending: ComposerFormattingModel.Pending) -> some View {
        switch pending {
        case .link:
            Button("Non", role: .cancel) { formatting.declinePending(pending); focused = .text }
            Button("Oui") { formatting.acceptPending(pending); focused = .text }
        case .linkChoice:
            Button("Sans le presse-papiers", role: .cancel) { formatting.declinePending(pending); focused = .text }
            Button("Oui [url=XXX]") { formatting.acceptLinkChoice(pending, attribute: true); focused = .text }
            Button("Oui [url]XXX[/url]") { formatting.acceptLinkChoice(pending, attribute: false); focused = .text }
        case .formatting:
            Button("Sans le presse-papiers", role: .cancel) { formatting.declinePending(pending); focused = .text }
            Button("Insérer") { formatting.acceptPending(pending); focused = .text }
        }
    }

    fileprivate func openImages() {
        imageInserted = false
        rangeImage = formatting.selectedRange
        isShowingImages = true
    }
}
