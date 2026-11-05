import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (AnswerView, reply mode) @ 2440d79. Differences: formatting toolbar (LOT-085, GAP-085);
// no GIF or upload panel yet (LOT-102, 155), smiley picker as a sheet from the toolbar (LOT-104, GAP-087);
// errors say whether anything was posted instead of the toast (GAP-100); draft per topic (GAP-092, UXD).
/// The composer sheet: a plain text editor, Send and Cancel; a new private message adds its recipient and subject
/// (LOT-128, legacy "À :" field, `QuoteMessageViewController.m:306-330` @ 21173e77). Thin: every rule is in
/// `ReplyComposerModel`.
///
/// The editor is SwiftUI's own `TextEditor` with the system keyboard type, so third-party keyboards work (legacy backlog
/// HFR-001) and the text is never rewritten under the cursor; the sheet's keyboard safe area keeps the caret visible.
struct ReplyComposerView: View {
    let model: ReplyComposerModel
    /// Called once with the reason, right before the sheet goes away.
    let onClose: (ReplyComposerModel.CloseReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Field?
    @State private var selection: TextSelection?
    @State private var picker: SmileyPickerModel?
    /// A smiley was inserted by the open picker: focus goes back to the editor when it closes, not after a plain "Fermer".
    @State private var smileyInserted = false
    /// The editor's selection when the picker opened: the sheet takes focus, so the live binding is not trusted.
    @State private var rangeForSmiley: Range<String.Index>?

    private enum Field: Hashable {
        case recipient, subject, text
    }

    @State private var formatting: ComposerFormattingModel

    init(model: ReplyComposerModel, onClose: @escaping (ReplyComposerModel.CloseReason) -> Void) {
        self.model = model
        self.onClose = onClose
        _formatting = State(initialValue: ComposerFormattingModel(composer: model, clipboard: SystemClipboard()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ComposerBanner(text: message, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        if model.mayHavePosted {
                            Button(model.isNewMessage ? "Voir les messages" : "Voir le sujet") { Task { await model.checkTopic() } }
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
                if model.isNewMessage { messageFields }
                editor
                FormattingToolbar(model: formatting) { focused = .text }
            }
            .navigationTitle(model.isNewMessage ? "Nouveau message" : "Répondre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Utiliser le presse-papiers ?", isPresented: askingClipboard, presenting: formatting.pending) { pending in
                switch pending {
                case .link:
                    Button("Non", role: .cancel) { formatting.declinePending(pending); focused = .text }
                    Button("Oui") { formatting.acceptPending(pending); focused = .text }
                case .formatting:
                    Button("Sans le presse-papiers", role: .cancel) { formatting.declinePending(pending); focused = .text }
                    Button("Insérer") { formatting.acceptPending(pending); focused = .text }
                }
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
        // Swiping down would close without the choice: blocked while there is text or a send runs.
        .interactiveDismissDisabled(model.closeNeedsChoice || model.isSending)
        .task {
            await model.start()
            formatting.placeCaretAtEnd()
            focused = firstEmptyField
        }
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

    /// Where typing starts: the first field of a new private message still empty, else the text.
    private var firstEmptyField: Field {
        guard model.isNewMessage else { return .text }
        if model.recipient.isEmpty { return .recipient }
        return model.subject.isEmpty ? .subject : .text
    }

    private var keepDraftNote: String {
        model.isNewMessage
            ? "Le brouillon est retrouvé au prochain message à ce destinataire."
            : "Le brouillon est retrouvé à la prochaine réponse dans ce sujet."
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
        rangeForSmiley = selectedRange
        smileyInserted = false
        picker = SmileyPickerModel(
            catalogue: SmileyPickerModel.bundledCatalogue(), store: services.store, account: services.account
        )
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
            .accessibilityLabel(model.isNewMessage ? "Texte du message" : "Texte de la réponse")
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

    /// Recipient and subject of a new private message, one line each, like HFR's own form (`R45b`).
    private var messageFields: some View {
        VStack(spacing: 0) {
            TextField("Destinataire", text: Binding(get: { model.recipient }, set: { model.update(recipient: $0) }))
                .focused($focused, equals: .recipient)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focused = .subject }
                .accessibilityLabel("Pseudo du destinataire")
                .padding(.vertical, 10)
            Divider()
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Smileys", systemImage: "face.smiling", action: openSmileys)
                .disabled(!model.canEdit)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") { Task { await model.requestClose() } }
            .disabled(model.isSending)
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSending {
                ProgressView().accessibilityLabel("Envoi en cours")
            } else {
                Button("Envoyer") { Task { await model.send() } }
                    .disabled(!model.canSend)
            }
        }
    }
}

/// A message above the editor, with an optional action.
private struct ComposerBanner<Actions: View>: View {
    let text: String
    let symbol: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).scaledFont(.callout).fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
