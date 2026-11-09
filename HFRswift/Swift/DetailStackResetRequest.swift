import SwiftUI

/// Split view only: a new value asks every `MessagesView` of the detail column to pop the
/// readers it pushed (internal links, in-topic search results). `RootTabView` sends it before
/// it replaces the detail root: changing the identity of the detail `NavigationStack` does not
/// pop a reader pushed with `navigationDestination(isPresented:)`, which then stays on top of
/// every later selection (#663). `nil` outside the split view.
private struct DetailStackResetRequestKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var detailStackResetRequest: UUID? {
        get { self[DetailStackResetRequestKey.self] }
        set { self[DetailStackResetRequestKey.self] = newValue }
    }
}
