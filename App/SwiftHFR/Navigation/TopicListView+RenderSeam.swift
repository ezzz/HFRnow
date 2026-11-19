import Foundation

/// Test seam (#1015): a scroll (the large title leaving or coming back) must not rebuild the list, its section headers or its rows.
/// Every such build re-applies the modifiers of every realised row and header, a cost that grows with the sections and rows.
extension TopicListView {
    /// What `counting` counts: the body, a section header (by group id) or a row (by topic id).
    enum RenderPart: Hashable {
        case body
        case header(String)
        case row(String)
    }

    #if DEBUG
    /// The builds of each part, per model (`ObjectIdentifier(model)`). Keys are never removed and an identifier can be reused once
    /// its model is freed, so a test reads a delta from a baseline taken after the list has settled.
    private(set) static var renders: [ObjectIdentifier: [RenderPart: Int]] = [:]
    /// The large title's visibility of each model's list, so a test can check the crossings it drives really happen.
    private(set) static var titleVisibilities: [ObjectIdentifier: TitleVisibility] = [:]
    #endif

    /// Passes `value` through; a debug build also counts one build of `part` for this list's model, and keeps `title`, the list's
    /// large-title visibility, when given.
    func counting<Value>(_ part: RenderPart, _ value: Value, title: TitleVisibility? = nil) -> Value {
        #if DEBUG
        Self.renders[ObjectIdentifier(model), default: [:]][part, default: 0] += 1
        if let title { Self.titleVisibilities[ObjectIdentifier(model)] = title }
        #endif
        return value
    }
}

/// Test seam (#870): the lists draw every row through `TopicRowView`; a debug build counts its builds per topic id, so a test
/// shows that each filter's rows reached it, not only the list's own row loop.
extension TopicRowView {
    #if DEBUG
    /// Builds of `body` per topic id. Ids are fixture ids and never removed: a test reads a delta from a baseline.
    @MainActor private(set) static var builds: [String: Int] = [:]
    #endif

    /// Counts one build of this row in a debug build.
    @MainActor func countingBuild() {
        #if DEBUG
        Self.builds[topic.id, default: 0] += 1
        #endif
    }
}
