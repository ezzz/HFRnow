import SwiftUI

/// Which root tab a view belongs to, and whether it sits in the compact `TabView` root.
/// Set by `RootTabView`; read by `MessagesView` (to register the topic being read) and by
/// `foldHandoffDestination()` (to push a topic after a fold).
struct FoldHandoffScope: Equatable {
    let tab: RootTabIdentifier
    let isCompactRoot: Bool
}

private struct FoldHandoffScopeKey: EnvironmentKey {
    static let defaultValue: FoldHandoffScope? = nil
}

extension EnvironmentValues {
    var foldHandoffScope: FoldHandoffScope? {
        get { self[FoldHandoffScopeKey.self] }
        set { self[FoldHandoffScopeKey.self] = newValue }
    }
}
