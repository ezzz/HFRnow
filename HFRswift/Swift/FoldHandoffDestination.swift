import SwiftUI

extension View {
    /// Pushes the topic that was open in the split view when the device is folded (or an iPad
    /// window becomes compact). Apply to the root content of each compact tab's
    /// `NavigationStack`; inert outside the compact `TabView` root.
    func foldHandoffDestination() -> some View {
        modifier(FoldHandoffDestination())
    }
}

private struct FoldHandoffDestination: ViewModifier {
    @Environment(\.foldHandoffScope) private var scope
    @State private var target: TopicNavigationTarget?
    private let store = FoldHandoffStore.shared

    private var isPresented: Binding<Bool> {
        Binding {
            target != nil
        } set: { isPresented in
            if !isPresented {
                target = nil
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: consumePendingPush)
            .onChange(of: store.pendingPush?.id) {
                consumePendingPush()
            }
            .navigationDestination(isPresented: isPresented) {
                if let target {
                    MessagesView(
                        topic: target.topic,
                        curPage: target.page,
                        maxPage: target.maxPage,
                        separatorNewMessages: target.separatorNewMessages,
                        initialLoadScroll: target.initialScroll,
                        initialFavoritePostFilterResult: target.initialFavoritePostFilterResult
                    )
                    .toolbar(.hidden, for: .tabBar)
                } else {
                    EmptyView()
                }
            }
    }

    private func consumePendingPush() {
        guard let scope, scope.isCompactRoot,
              let pending = store.consumePendingPush(for: scope.tab) else {
            return
        }
        target = pending
    }
}
