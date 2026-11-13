import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (AnswerView, reply mode; new topic: sub-category `Picker`, :395-420, GAP-098; edit mode,
// GAP-096) @ 2440d79; the "Brouillons" button (LOT-101, GAP-093) is `AnswerView.swift:783-796` @ 87fe0d1c.
// Differences: formatting toolbar (LOT-085, GAP-085); image panel (LOT-102, GAP-090),
// GIF panel (`GifPanel`, LOT-155, GAP-089), smiley picker as a sheet from the toolbar (LOT-104, GAP-087);
// errors say whether anything was posted instead of the toast (GAP-100); draft per topic (GAP-092, UXD); the formatting bar is
// pinned to the keyboard safe area and off while the recipient or subject has focus (#599, GAP-085).
// Layout of HFRswift/Swift/AnswerView.swift (body `:458-482`, `ComposerHeader` `:768-819`, composerToolbar `:940-962`) @ 87fe0d1c:
// close `xmark` and drafts `tray` on the left, send `arrow.up` on the right, the editor in a rounded card, the control row and the
// "Aa" bar under it (#653, `ComposerControlRow`). Differences: on an iPhone the composer is a card docked on the keyboard that
// grows with the text up to a cap (`ComposerHeight`, `ComposerCardLayout`, GAP-653, b·operator); in the reader that card is a bar
// docked at the bottom of the page, the page scrollable above it with the keyboard up, its taps ignored (#853,
// `ComposerPlacement`), elsewhere a sheet; the full-screen toggle in the editor's corner; inserted images as chips in the card;
// on an iPhone the control row inside the card and close, drafts and send as small floating buttons (#854, `ComposerChrome`).
/// The composer, a sheet or the reader's docked bar: a plain text editor, close and Send; a new topic adds its subject and
/// sub-category (LOT-089); a new private message adds its recipient and subject
/// (LOT-128, legacy "À :" field, `QuoteMessageViewController.m:306-330` @ 21173e77). Thin: every rule is in
/// `ReplyComposerModel`.
///
/// The editor is SwiftUI's own `TextEditor` with the system keyboard type, so third-party keyboards work (legacy backlog
/// HFR-001) and the text is never rewritten under the cursor; the keyboard safe area (the sheet's, or the reader's under the
/// docked bar) keeps the caret visible.
struct ReplyComposerView: View {
    let model: ReplyComposerModel
    /// A sheet, or the reader's bar docked on the keyboard (#853): the presenter then removes it in `onClose`.
    let placement: ComposerPlacement
    /// Called once with the reason, right before the composer goes away.
    let onClose: (ReplyComposerModel.CloseReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    /// Hosted layout tests only (#854); nil in the app.
    @Environment(\.composerLayoutProbe) private var probe
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
    /// The archived drafts' picker is open (LOT-101).
    @State private var isShowingArchive = false
    /// The docked card's parts as last laid out (#653).
    @State private var measured = ComposerCardLayout()

    init(
        model: ReplyComposerModel, placement: ComposerPlacement = .sheet, onClose: @escaping (ReplyComposerModel.CloseReason) -> Void
    ) {
        self.model = model
        self.placement = placement
        self.onClose = onClose
        _formatting = State(initialValue: ComposerFormattingModel(composer: model, clipboard: SystemClipboard()))
        _imageUpload = State(initialValue: ImageUploadModel(services: model.imageUploadServices))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ComposerHeader(
                    title: title, isSending: model.isSending, canSend: model.canSend, drafts: drafts,
                    floats: chrome.headerFloats,
                    close: { Task { await model.requestClose() } }, send: { Task { await model.send() } }
                )
                .padding(.horizontal, 16)
                .padding(.top, chrome.headerFloats ? 10 : 14)
                .padding(.bottom, 6)
                banners
                if model.hasSubjectField { messageFields }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.top = $0 }
            editorCard
                .padding(.horizontal, 16)
                .padding(.vertical, ComposerCardLayout.gap)
            // Just under the editor, so it moves with the card and the keyboard (#653); one view kept across focus changes,
            // after the fields, so moving between them never moves it (#599). Not `.keyboard` placement: that is an input
            // accessory rebuilt for each focused field (recipient, subject, text), and gone without an on-screen keyboard.
            // On an iPhone it is inside the card instead, on its bottom edge (#854).
            if !chrome.controlsInCard { measuredControls }
        }
        // Docked at partial height the bar is as tall as its card; a sheet, or "Plein écran", fills what it is given.
        .frame(maxHeight: placement == .docked && height == .partial ? nil : .infinity, alignment: .top)
        .appScreenBackground()
        .modifier(DockedComposerBar(isDocked: placement == .docked, height: height))
        .gifPanel(services: model.gifServices, formatting: formatting, request: $gifRequested) { focused = .text }
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
        .sheet(item: $picker, onDismiss: { if smileyInserted { focused = .text } }, content: { picker in
            SmileyPickerView(model: picker) { insertSmiley($0) }
        })
        .imageUploadSheet(
            isPresented: $isShowingImages, model: imageUpload,
            onDismiss: { if imageInserted { focused = .text } },
            onInsert: { insertImage($0) }
        )
        .modifier(ComposerSheetSettings(
            isSheet: placement == .sheet, isPhone: isPhone, detent: detent,
            dismissDisabled: model.closeNeedsChoice || model.isSending
        ))
        .sheet(isPresented: $isShowingArchive, onDismiss: { focused = .text }, content: {
            ArchivedDraftsView(model: model) {
                isShowingArchive = false
                formatting.placeCaretAtEnd()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        })
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
        .onChange(of: measured, initial: true) { _, layout in probe?.layout(layout) }
        // The banners appear above the editor, away from VoiceOver's focus: say them when they appear (LOT-163).
        .onChange(of: model.errorMessage) { _, text in ReaderAccessibility.announce(text) }
        .onChange(of: model.draftWarning) { _, text in ReaderAccessibility.announce(text) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.flushDraft() } }
        }
        .onChange(of: model.closeReason) { _, reason in
            guard let reason else { return }
            onClose(reason)
            if placement == .sheet { dismiss() } // the docked bar's presenter removes it in `onClose`
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

    private var editorCard: some View {
        ComposerEditorCard(
            model: model, formatting: formatting, selection: $selection, focused: $focused, chips: model.shownImageChips,
            editorHeight: height == .partial ? measured.editorHeight : nil, toggle: offersHeightToggle ? height.toggled : nil,
            onToggle: { chosenHeight = height.toggled }, removeChip: removeImage,
            measure: { text, line in measured.text = text; measured.line = line },
            controls: chrome.controlsInCard ? AnyView(measuredControls) : nil
        )
    }

    @ViewBuilder
    private var banners: some View {
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
            if model.offersSubcategories, ComposerSubcategoryRow.shows(model.picker) {
                ComposerSubcategoryRow(model: model)
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

    /// An iPhone's lighter composer: the controls in the card, floating buttons (#854).
    private var chrome: ComposerChrome { ComposerChrome(isPhone: isPhone) }

    /// The controls, their height measured for the docked card (`ComposerCardLayout.controls`).
    private var measuredControls: some View {
        controls
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.controls = $0 }
            .composerProbe(.controls)
    }

    /// An iPhone in regular height: partial height first, and the toggle (#653).
    private var offersHeightToggle: Bool {
        ComposerHeight.offersToggle(isPhone: isPhone, verticalSizeClass: verticalSizeClass)
    }

    private var height: ComposerHeight {
        ComposerHeight.shown(
            chosen: chosenHeight, isPhone: isPhone, verticalSizeClass: verticalSizeClass, largeText: dynamicTypeSize.isAccessibilitySize
        )
    }

    /// The sheet's only detent: the docked card's height at partial height (`ComposerCardLayout`), `.large` at full.
    private var detent: PresentationDetent {
        var layout = measured
        layout.chips = model.shownImageChips.isEmpty ? 0 : ComposerImageChipsRow.height
        return height.detent(cardHeight: layout.cardHeight)
    }

    /// The "Aa" bar when shown, above the control row: one view kept across focus changes (#599).
    private var controls: some View {
        VStack(spacing: 0) {
            if formatting.isBarShown { formattingBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            ComposerControlRow(
                model: model, formatting: formatting, offersGif: model.gifServices.isAvailable,
                openSmileys: openSmileys, openGif: { gifRequested = true }, openImages: openImages,
                refocus: { focused = ComposerBarFocus.focus(afterBarActionFrom: focused) }, inCard: chrome.controlsInCard
            )
        }
        .animation(.easeInOut(duration: 0.2), value: formatting.isBarShown)
    }

    /// Off while the recipient or subject has focus; a tap never takes focus from them (`ComposerBarFocus`, #599).
    private var formattingBar: some View {
        let allowsBar = ComposerBarFocus.allowsBar(focused: focused)
        // `.plain` buttons draw no disabled state: the bar dims itself, as `FormattingToolbar` does for `isEnabled`.
        return FormattingToolbar(
            model: formatting, refocus: { focused = ComposerBarFocus.focus(afterBarActionFrom: focused) }, inCard: chrome.controlsInCard
        )
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

    /// The panel's snippet at the caret it had; an upload of the panel also gets its chip in the card (#653).
    fileprivate func insertImage(_ snippet: String) {
        formatting.selectedRange = rangeImage
        formatting.insert(snippet)
        imageInserted = true
        if let image = imageUpload.uploadedImage(writing: snippet) {
            model.imageChips.append(ComposerImageChip(snippet: snippet, thumbnail: image.miniURL ?? image.mediumURL ?? image.fullURL))
        }
    }

    /// The chip's ✕: one step of the history, the caret at the end.
    fileprivate func removeImage(_ chip: ComposerImageChip) {
        if model.removeImage(chip) { formatting.placeCaretAtEnd() }
    }

    /// LOT-101's drafts button, where the composer archives drafts (a topic's reply).
    fileprivate var drafts: ComposerHeader.Drafts? {
        guard model.offersArchivedDrafts else { return nil }
        return ComposerHeader.Drafts(hasDrafts: !model.archivedDrafts.isEmpty, isEnabled: model.canEdit) {
            Task {
                await model.refreshArchivedDrafts()
                isShowingArchive = true
            }
        }
    }
}
