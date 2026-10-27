import SwiftUI

/// One `NavigationSplitView` for iPhone, iPad and foldables: forums, topics, messages. On a compact width it collapses to a
/// stack by itself.
struct AdaptiveNavigationView: View {
    @State private var navigation: NavigationModel
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    init(environment: AppEnvironment) {
        let forums = ForumListModel(dataSource: environment.dataSource, accountName: environment.accountName)
        _navigation = State(initialValue: NavigationModel(dataSource: environment.dataSource, forums: forums))
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
            MessagePlaceholderView(topic: navigation.selectedTopic)
        }
    }
}
