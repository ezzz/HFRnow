import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (the segmented `Picker("Filtre")`, `:613-640`) @ 87fe0d1c. Differences: none visible.
/// The segmented Tous / Favoris / Suivis / Lus control, bound to the shared `TopicFilterModel`. One component for every list
/// that offers the filter. Without `canFilter` only "Tous" can be chosen, as legacy does logged out, and the control reads
/// "Tous" while the stored choice is kept.
struct TopicFlagFilterPicker: View {
    @Bindable var filter: TopicFilterModel
    var canFilter: Bool

    var body: some View {
        // `.disabled` on a segment does nothing on iOS 27, so the binding refuses what legacy disables (`MainWindow.swift:683-695`
        // @ 87fe0d1c): logged out, a tap on Favoris, Suivis or Lus must not overwrite the persisted choice.
        let selection = Binding(
            get: { canFilter ? filter.flag : .all },
            set: { if canFilter || $0 == .all { filter.flag = $0 } }
        )
        Picker("Filtre", selection: selection) {
            Text("Tous").tag(TopicListFlag.all)
            Text("Favoris").tag(TopicListFlag.favorites).disabled(!canFilter)
            Text("Suivis").tag(TopicListFlag.tracked).disabled(!canFilter)
            Text("Lus").tag(TopicListFlag.read).disabled(!canFilter)
        }
        .pickerStyle(.segmented)
    }
}
