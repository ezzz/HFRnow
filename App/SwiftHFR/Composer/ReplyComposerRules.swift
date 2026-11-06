import Foundation
import HFRStorage

/// Rules shared by the composer's text fields and its draft warnings.
extension ReplyComposerModel {
    static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Distinct characters with a scalar above U+FFFF, in order: HFR cuts the message at the first one (Q-3, `W12`).
    static func unsupportedCharacters(in text: String) -> [Character] {
        var refused: [Character] = []
        for character in text where character.unicodeScalars.contains(where: { $0.value > 0xFFFF }) {
            if !refused.contains(character) { refused.append(character) }
        }
        return refused
    }

    static func draftWarning(for error: any Error) -> String {
        if case .loadFailed = error as? DraftError {
            return "Les brouillons sont illisibles pour le moment : ce texte ne sera pas sauvegardé si vous fermez."
        }
        return "Le brouillon n’a pas pu être enregistré. Le texte reste affiché ; copiez-le si vous fermez."
    }
}
