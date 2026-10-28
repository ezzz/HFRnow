import HFRStorage
import SwiftUI

/// One `NavigationSplitView` for iPhone, iPad and foldables: forums, topics, messages. On a compact width it collapses to a
/// stack by itself.
struct AdaptiveNavigationView: View {
    @State private var navigation: NavigationModel
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar
    private let reader: ReaderServices

    init(environment: AppEnvironment) {
        reader = environment.reader
        // The legacy start tab (LOT-119): the app opens on the chosen list, not on the sidebar.
        let startup = UserDefaultsSettingsStore().value(for: SettingKey.startupScreen).initialSource
        _preferredCompactColumn = State(initialValue: startup == nil ? .sidebar : .content)
        let forums = ForumListModel(
            dataSource: environment.dataSource, visibility: environment.visibility, accountName: environment.accountName
        )
        _navigation = State(initialValue: NavigationModel(
            dataSource: environment.dataSource, forums: forums, sessionIsLoggedIn: environment.isLoggedIn,
            topicPages: environment.topicPages, renderOptions: environment.reader.settings.renderOptions,
            startupSource: startup
        ))
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            ForumListView(navigation: navigation)
        } content: {
            if let source = navigation.selectedSource {
                TopicListView(model: navigation.topicList(for: source), selection: $navigation.selectedTopic)
                    .id(source)
            } else {
                ContentUnavailableView("Choisissez un forum", systemImage: "list.bullet")
            }
        } detail: {
            if let topic = navigation.selectedTopic, let model = navigation.reader(for: topic) {
                TopicReaderView(model: model, services: reader)
                    .id(topic.id)
            } else {
                MessagePlaceholderView(topic: navigation.selectedTopic)
            }
        }
    }
}
