import Foundation

// Out of TopicReaderView.swift, which reached SwiftLint's file length with LOT-134's entry.
/// The reader a link pushed, identified by its model.
struct LinkedReader: Hashable {
    let model: TopicReaderModel

    static func == (lhs: LinkedReader, rhs: LinkedReader) -> Bool { lhs.model === rhs.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }
}
