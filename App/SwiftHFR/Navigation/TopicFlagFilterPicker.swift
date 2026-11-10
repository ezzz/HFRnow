import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (the segmented `Picker("Filtre")`, `:613-640`) @ 87fe0d1c. Differences: none visible.
/// The segmented Tous / Favoris / Suivis / Lus control, bound to the shared `TopicFilterModel`. One component for every list
/// that offers the filter; disabled, it reads "Tous" and keeps the stored choice.
struct TopicFlagFilterPicker: View {
    @Bindable var filter: TopicFilterModel
    var isEnabled: Bool

    var body: some View {
        Picker("Filtre", selection: Binding(get: { isEnabled ? filter.flag : .all }, set: { filter.flag = $0 })) {
            Text("Tous").tag(TopicListFlag.all)
            Text("Favoris").tag(TopicListFlag.favorites)
            Text("Suivis").tag(TopicListFlag.tracked)
            Text("Lus").tag(TopicListFlag.read)
        }
        .pickerStyle(.segmented)
        .disabled(!isEnabled)
    }
}
