/// Output of `MPStorageMerge.merge`.
public struct MPStorageMergeResult: Sendable, Hashable {
    /// The merged document; equal to `theirs` when `needsWrite` is false.
    public var document: MPStorageDocument
    /// Decisions the merge had to take.
    public var conflicts: [MPStorageConflict]
    /// Whether the merged document differs from the one on the forum, i.e. must be written.
    public var needsWrite: Bool

    /// Creates a result.
    public init(document: MPStorageDocument, conflicts: [MPStorageConflict], needsWrite: Bool) {
        self.document = document
        self.conflicts = conflicts
        self.needsWrite = needsWrite
    }
}
