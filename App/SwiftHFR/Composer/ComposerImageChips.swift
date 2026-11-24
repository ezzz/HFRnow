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

/// The ✕ of a chip: an 18 pt glyph (growing with Dynamic Type) in a 44 pt hit region (#1156).
struct ComposerImageChipCross: View {
    let isEnabled: Bool
    let action: () -> Void
    /// The glyph stops growing here: a 56 pt thumbnail must stay visible at accessibility text sizes; the region stays 44 pt.
    private static let maximumGlyph: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 18

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .font(.system(size: min(glyph, Self.maximumGlyph)))
                .minimumHitRegion()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Retirer l'image")
    }
}

/// The chips row at the top of the docked card: one thumbnail per image still in the text, each with its ✕.
struct ComposerImageChipsRow: View {
    /// The row's height in the card: a 56 pt thumbnail under a 10 pt margin.
    static let height: CGFloat = 66

    let chips: [ComposerImageChip]
    /// The panel's thumbnail loader (#1193): the cookie-less client, the rehost host only.
    let thumbnails: SmileyImageLoader
    let isEnabled: Bool
    let remove: (ComposerImageChip) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                    RemoteThumbnail(url: chip.thumbnail, loader: thumbnails)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        ComposerImageChipCross(isEnabled: isEnabled) { remove(chip) }
                            // The 44 pt region is centred on where the 18 pt glyph sat (2 pt in from the corner); its top
                            // overhang stops at the row's 10 pt margin so the scroll view does not clip it (#1156).
                            .offset(x: 11, y: -10)
                    }
                    // An earlier chip draws over the next thumbnail, so its ✕ region (11 pt past the thumbnail, the gap is 8)
                    // is never covered by it (#1156).
                    .zIndex(Double(chips.count - index))
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
