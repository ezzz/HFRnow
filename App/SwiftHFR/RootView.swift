import SwiftUI

/// Root screen: the adaptive navigation. The login lot puts the account screens around it.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        AdaptiveNavigationView(environment: environment)
    }
}
