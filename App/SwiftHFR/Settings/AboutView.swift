import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (aboutSection) @ 87fe0d1c. Differences: version, topic links, changelog and
// credits on one screen, opened by the Plus entry "Crédits" (operator decision 2026-10-28, GAP-151, LOT-120 spec).
/// About (LOT-120): the version and build, the app's two HFR topics (opened in the reader), the changelog and the credits.
struct AboutView: View {
    @State private var model: AboutModel
    private let services: ReaderServices
    private let composer: ComposerServices?

    /// About over the environment's topic pages and reader services (the one the open session built, LOT-081).
    init(environment: AppEnvironment) {
        _model = State(initialValue: AboutModel(
            topicPages: environment.topicPages, renderOptions: environment.reader.settings.renderOptions
        ))
        services = environment.reader
        composer = environment.composer
    }

    var body: some View {
        @Bindable var model = model
        List {
            Section("Version") {
                LabeledContent("Version", value: model.version.display)
            }
            Section {
                ForEach(AboutTopicLink.allCases, id: \.self) { link in
                    Button { model.selected = link } label: {
                        HStack {
                            Label(link.title, systemImage: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .scaledFont(.footnote).fontWeight(.semibold)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            } header: {
                Text("Sujets HFR+")
            } footer: {
                Text("Les sujets de l'app sur le forum, ouverts dans l'app.")
            }
            Section {
                NavigationLink { ChangelogView().appScreenBackground() } label: {
                    Label("Nouveautés", systemImage: "sparkles")
                }
                NavigationLink { StaticPageView(page: .credits).appScreenBackground() } label: {
                    Label(StaticPage.credits.title, systemImage: "info.circle")
                }
            }
        }
        .navigationTitle(StaticPage.credits.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $model.selected) { link in
            if let reader = model.reader(for: link) {
                TopicReaderView(model: reader, services: services, composer: composer)
            } else {
                ContentUnavailableView("Sujet introuvable", systemImage: "questionmark.folder").appScreenBackground()
            }
        }
    }
}

/// "Nouveautés": the legacy problems SwiftHFR fixes, per section.
struct ChangelogView: View {
    private let changelog = Changelog.bundled()

    var body: some View {
        List {
            if changelog.entries.isEmpty {
                ContentUnavailableView("Aucune nouveauté", systemImage: "sparkles")
            }
            ForEach(changelog.sections, id: \.self) { section in
                Section(section.title) {
                    ForEach(Array(changelog.entries(in: section).enumerated()), id: \.offset) { _, entry in
                        Text(entry.summary).scaledFont(.body)
                    }
                }
            }
        }
        .navigationTitle("Nouveautés")
        .navigationBarTitleDisplayMode(.inline)
    }
}
