import Foundation

// Port of HFRswift/Swift/ReplyComposer.swift (ReplyTextInsertionEngine.insert) @ 2440d79. Differences: the insertion itself
// is `ComposerFormattingModel.insert(smiley:at:)` (#910); only the snippet is here (GAP-087).
/// What a smiley code writes into the reply text (LOT-104): the snippet legacy built for a smiley (`insertSmileyCode`,
/// `AnswerView.swift:~517`: the code between two spaces).
enum SmileyInsertion {
    /// What is written for `code`: the code between two spaces, as legacy did.
    static func snippet(for code: String) -> String {
        " \(code) "
    }
}
