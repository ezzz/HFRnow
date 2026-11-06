/// A node of `JSONTreeEncoder`'s tree under construction: containers are filled after they are handed out, so they are
/// shared references until the tree is read back as a `JSONValue`.
final class JSONTreeNode {
    enum Content {
        case value(JSONValue)
        case object([String: JSONTreeNode])
        case array([JSONTreeNode])
        /// What a super encoder writes, read when the tree is finished: the super may write a value, an array or an
        /// object, and only then does the encoder know which.
        case deferred(JSONTreeEncoder)

        func isSameKind(as other: Content) -> Bool {
            switch (self, other) {
            case (.object, .object), (.array, .array): true
            default: false
            }
        }
    }

    var content: Content

    init(_ content: Content) { self.content = content }

    /// The finished value.
    var value: JSONValue {
        switch content {
        case .value(let value): value
        case .object(let members): .object(members.mapValues(\.value))
        case .array(let items): .array(items.map(\.value))
        case .deferred(let encoder): encoder.node?.value ?? .object([:])
        }
    }

    /// Sets `key` of an object node.
    func set(_ key: String, _ node: JSONTreeNode) {
        guard case .object(var members) = content else { return }
        members[key] = node
        content = .object(members)
    }

    /// Appends to an array node.
    func append(_ node: JSONTreeNode) {
        guard case .array(var items) = content else { return }
        items.append(node)
        content = .array(items)
    }

    /// The number of items of an array node (the next item's index); only an unkeyed container, always backed by an
    /// array node, asks.
    var count: Int {
        guard case .array(let items) = content else { return 0 }
        return items.count
    }
}
