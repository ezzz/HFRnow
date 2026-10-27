import SwiftUI

/// Placeholder root screen until the navigation lot (LOT-082) replaces it; carries the account menu (LOT-081).
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountMenuButton()
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AccountsModel.preview())
}
