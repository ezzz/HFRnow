import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (body: `ReplyTextEditor` in `composerEditorStyle`, `:470-482`, `:1748-1760`) @ 87fe0d1c.
// Differences: SwiftUI's `TextEditor` (LOT-084); on an iPhone the card is as tall as its text up to a cap, then the editor scrolls
// inside it (#653, `ComposerCardLayout`); inserted images as chips at its top; the full-screen toggle in its corner; on an iPhone
// the control row on its bottom edge (#854) (GAP-653).
/// The docked card's editor (#653, operator reference of 2026-11-10): the image chips, then the text in a rounded glass card,
/// with the "Plein écran" / "Réduire" toggle in its top corner where the composer offers it and, on an iPhone, the controls
/// on its bottom edge, under the text (#854, operator 2026-11-12: as the buttons inside the Claude app's composer).
struct ComposerEditorCard: View {
    let model: ReplyComposerModel
    let formatting: ComposerFormattingModel
    @Binding var selection: TextSelection?
    let focused: FocusState<ComposerField?>.Binding
    /// The chips of the images still in the text.
    let chips: [ComposerImageChip]
    /// The editor's height at partial height (`ComposerCardLayout.editorHeight`); nil fills the sheet (full height).
    let editorHeight: CGFloat?
    /// The toggle's target, nil where the composer has no toggle (an iPad, compact height).
    let toggle: ComposerHeight?
    let onToggle: () -> Void
    let removeChip: (ComposerImageChip) -> Void
    /// The text's and one line's laid-out heights, for the card's height.
    let measure: (_ text: CGFloat, _ line: CGFloat) -> Void
    /// The control row inside the card, under the editor (an iPhone, `ComposerChrome.controlsInCard`); nil keeps it outside.
    /// Type-erased so the card stays one non-generic type for its static helpers.
    var controls: AnyView?
    @State private var textHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !chips.isEmpty {
                ComposerImageChipsRow(chips: chips, isEnabled: model.canEdit, remove: removeChip)
                    .frame(height: ComposerImageChipsRow.height)
            }
            editor
                .frame(height: editorHeight)
                .frame(maxHeight: editorHeight == nil ? .infinity : nil)
                .padding(.leading, 8)
                .padding(.trailing, toggle == nil ? 8 : 36)
                .overlay(alignment: .topTrailing) { toggleButton }
            // The editor stops at its cap (`ComposerCardLayout.editorHeight`): the text never covers the controls.
            if let controls { controls }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var toggleButton: some View {
        if let toggle {
            let expands = toggle == .full
            Button(action: onToggle) {
                Image(systemName: expands ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expands ? "Plein écran" : "Réduire")
        }
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.text }, set: { model.update(text: $0) }), selection: $selection)
            .focused(focused, equals: .text)
            .scaledFont(.body)
            .scrollContentBackground(.hidden)
            .disabled(!model.canEdit)
            // The text as the editor lays it out (`TextEditor` keeps 5 pt of line padding on each side): the card's height.
            .background(alignment: .topLeading) { textMeasure }
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

    /// Hidden copies of the text and of one line, laid out at the editor's width.
    private var textMeasure: some View {
        ZStack(alignment: .topLeading) {
            Text(Self.measured(model.text))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0; measure(textHeight, lineHeight) }
            Text(verbatim: " ")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0; measure(textHeight, lineHeight) }
        }
        .scaledFont(.body)
        .padding(.horizontal, 5)
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .accessibilityHidden(true)
    }

    /// The text to measure: a trailing new line counts as a line, as in the editor, and an empty text as one.
    static func measured(_ text: String) -> String {
        text.isEmpty || text.hasSuffix("\n") ? text + " " : text
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
}
