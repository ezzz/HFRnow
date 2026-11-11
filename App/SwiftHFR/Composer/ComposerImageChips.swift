import Foundation
import HFRModels
import SwiftUI

/// An image the composer's panel inserted (#653, operator reference of 2026-11-10: "an inserted image shows as a thumbnail inside
/// the card, above the text, with an ✕ to remove it", the Claude app's attachment chip). The snippet stays in the text where the
/// panel put it, as legacy (`AnswerView.swift:646-676` @ 2440d79), so what is posted and saved as a draft does not change; the
/// chip previews it and its ✕ takes the snippet out of the text as one undoable step. Only the panel's own uploads get a chip
/// (their thumbnail is the host's mini rendition, as the panel's history shows it); a link typed by hand is not loaded.
struct ComposerImageChip: Identifiable, Equatable {
    let id = UUID()
    /// The BBCode the panel inserted.
    let snippet: String
    /// The host's smallest rendition, shown in the chip.
    let thumbnail: URL

    /// The chips whose snippet is still in `text`: typing, "Vider le texte" or an undo that takes it out hides the chip, a redo
    /// that puts it back shows it again.
    static func shown(_ chips: [ComposerImageChip], in text: String) -> [ComposerImageChip] {
        chips.filter { text.contains($0.snippet) }
    }

    /// `text` without the last occurrence of this chip's snippet (the one inserted last); nil when it is not there any more.
    func removed(from text: String) -> String? {
        guard let range = text.range(of: snippet, options: .backwards) else { return nil }
        return text.replacingCharacters(in: range, with: "")
    }
}

extension ReplyComposerModel {
    /// The chips of the images still in the text.
    var shownImageChips: [ComposerImageChip] { ComposerImageChip.shown(imageChips, in: text) }

    /// The chip's ✕: its snippet leaves the text as one step of the history; false when nothing changed (locked, or the
    /// snippet already gone).
    @discardableResult
    func removeImage(_ chip: ComposerImageChip) -> Bool {
        guard canEdit, let without = chip.removed(from: text) else { return false }
        update(text: without)
        return true
    }
}

extension ImageUploadModel {
    /// The panel's upload that wrote `snippet` with the current link setting; nil for a link typed by hand.
    func uploadedImage(writing snippet: String) -> RehostedImage? {
        history.first { image in image.availableVariants.contains { self.snippet(for: image, variant: $0) == snippet } }
    }
}

/// The chips row at the top of the docked card: one thumbnail per image still in the text, each with its ✕.
struct ComposerImageChipsRow: View {
    /// The row's height in the card: a 56 pt thumbnail under a 10 pt margin.
    static let height: CGFloat = 66

    let chips: [ComposerImageChip]
    let isEnabled: Bool
    let remove: (ComposerImageChip) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    AsyncImage(url: chip.thumbnail) { phase in
                        if let loaded = phase.image { loaded.resizable().scaledToFill() } else { Color.secondary.opacity(0.2) }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        Button { remove(chip) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .accessibilityLabel("Retirer l'image")
                        .padding(2)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Image insérée")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
    }
}
