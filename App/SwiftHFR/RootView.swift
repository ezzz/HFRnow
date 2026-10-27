import SwiftUI

/// Placeholder root screen until the login (LOT-081) and navigation (LOT-082) lots replace it.
struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("HFRKit") {
                    ForEach(EngineInfo.linkedModules, id: \.self) { module in
                        Label(module, systemImage: "shippingbox")
                    }
                }
            }
            .navigationTitle("HFR")
        }
    }
}

#Preview {
    RootView()
}
