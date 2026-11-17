import HFRModels
import SwiftUI

// Port of HFRswift/Swift/AQPlusView.swift (AQPlusView) and Classes/AQTableViewController.m @ 87fe0d1c (GAP-005). Differences: rows
// are `Button`s opening the reader at the message's page and anchor (issues #105, #106) in the Plus stack, not the legacy topic
// row view; a failed load keeps the rows and shows a retry; the list is a plain `List`, not the topic row styles (no flag cues).
/// The Alertes Qualitay list: one row per report, bold while new, opening the reported message.
struct QualityAlertsView: View {
    let model: QualityAlertsModel
    let environment: AppEnvironment
    @State private var opened: QualityAlertsModel.Row?
    /// This screen has asked for its list. Per screen, not on the model: legacy builds a new view model on every push
    /// (`PlusTab.swift:38`, `AQPlusView.swift:337, 436-441` @ 87fe0d1c), so each visit fetches and marks the list seen, while coming
    /// back from a message keeps the screen and its list.
    @State private var hasRequestedList = false

    var body: some View {
        List {
            if let failure = model.failure, !model.rows.isEmpty {
                Label(failure.title, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            ForEach(model.rows) { row in
                QualityAlertRow(row: row, now: .now) { opened = row }
            }
        }
        .overlay {
            QualityAlertsPlaceholder(model: model)
        }
        .navigationTitle("Alertes Qualitay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Actualiser", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.isLoading)
            }
        }
        .navigationDestination(item: $opened) { row in
            if let target = row.target {
                QualityAlertReaderScreen(target: target, title: row.title, environment: environment)
            }
        }
        .appScreenBackground()
        .task {
            guard !hasRequestedList else { return }
            hasRequestedList = true
            await model.load()
        }
        .refreshable { await model.load() }
    }
}

/// What stands in for the rows: the spinner of the first load, the failure with its retry, or the empty list.
private struct QualityAlertsPlaceholder: View {
    let model: QualityAlertsModel

    var body: some View {
        if model.rows.isEmpty {
            if model.isLoading || !model.hasLoaded {
                ProgressView("Chargement…")
            } else if let failure = model.failure {
                ContentUnavailableView {
                    Label(failure.title, systemImage: "bell.slash")
                } description: {
                    Text(failure.detail)
                } actions: {
                    if failure != .unavailable {
                        Button("Réessayer") { Task { await model.load() } }
                            .appProminentButtonStyle()
                    }
                }
            } else {
                ContentUnavailableView("Aucune AQ", systemImage: "bell")
            }
        }
    }
}

private struct QualityAlertRow: View {
    let row: QualityAlertsModel.Row
    let now: Date
    let open: () -> Void

    var body: some View {
        if row.target != nil {
            Button(action: open) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading) {
            Text(row.title)
                .scaledFont(.headline)
                .bold(row.isNew)
                .foregroundStyle(row.isNew ? Color.primary : Color.secondary)
            HStack {
                Text("par \(row.item.initiator)")
                Spacer()
                if let age = QualityAlertAge.label(since: row.item.publishedAt, now: now) { Text(age) }
            }
            .scaledFont(.footnote).foregroundStyle(.secondary)
            Text(row.item.comment.isEmpty ? row.item.title : "\(row.item.title)\n\(row.item.comment)")
                .scaledFont(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The reader of one report: its model lives in the view's state, so a redraw never reloads the page.
private struct QualityAlertReaderScreen: View {
    let environment: AppEnvironment
    @State private var reader: TopicReaderModel

    init(target: ReaderTarget, title: String, environment: AppEnvironment) {
        self.environment = environment
        _reader = State(initialValue: TopicReaderModel(
            target: target, title: title, source: environment.topicPages, renderOptions: environment.reader.settings.renderOptions
        ))
    }

    var body: some View {
        TopicReaderView(model: reader, services: environment.reader, composer: environment.composer)
    }
}
