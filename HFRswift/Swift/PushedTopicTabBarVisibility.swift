import SwiftUI

extension View {
    /// Tab bar visibility for a topic pushed on a navigation stack. In the compact `TabView`
    /// root (iPhone, iPhone Duo cover screen) the pushed topic hides the tab bar, as before.
    /// Inside the split views of the regular/regular root (iPad, unfolded iPhone Duo) the tab bar
    /// stays visible next to the list (HIG Tab bars: "Make sure the tab bar is visible when
    /// people navigate to different sections of your app").
    func hfrPushedTopicTabBarVisibility() -> some View {
        modifier(PushedTopicTabBarVisibility())
    }
}

private struct PushedTopicTabBarVisibility: ViewModifier {
    @Environment(\.foldHandoffScope) private var scope

    func body(content: Content) -> some View {
        content.toolbar(scope?.isCompactRoot == false ? .automatic : .hidden, for: .tabBar)
    }
}
