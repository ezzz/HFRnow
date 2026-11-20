import SwiftUI

// Out of TopicReaderView.swift, which reached SwiftLint's file length with LOT-134's entry.
/// The reader a link pushed, identified by its model.
struct LinkedReader: Hashable {
    let model: TopicReaderModel

    static func == (lhs: LinkedReader, rhs: LinkedReader) -> Bool { lhs.model === rhs.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }

    /// The binding of the navigation destination: set to nil by the system's back, it closes the linked reader.
    @MainActor static func binding(of model: TopicReaderModel) -> Binding<LinkedReader?> {
        Binding(
            get: { model.linkedReader.map(LinkedReader.init) },
            set: { if $0 == nil { model.closeLinkedReader() } }
        )
    }
}
