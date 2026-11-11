import HFRStorage
import Observation

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListView: `selectedFlag`, `@AppStorage("HFRswiftGlobalTopicListFlag")`) @ 87fe0d1c.
// Differences: a logged-out list shows "Tous" without overwriting the stored choice (legacy wrote "Tous" back); GAP-023.
/// The Tous / Favoris / Suivis / Lus choice, one for every list that offers it and kept across launches. Lists read it
/// when they appear; the `TopicFlagFilterPicker` writes it. Built once per navigation so it can serve more lists (#593).
@MainActor
@Observable
final class TopicFilterModel {
    var flag: TopicListFlag {
        didSet { if flag != oldValue { settings.set(flag, for: SettingKey.topicListFlag) } }
    }

    @ObservationIgnored private let settings: any SettingsStore

    /// Reads the stored choice (legacy key `HFRswiftGlobalTopicListFlag`).
    init(settings: any SettingsStore) {
        self.settings = settings
        flag = settings.value(for: SettingKey.topicListFlag)
    }
}
