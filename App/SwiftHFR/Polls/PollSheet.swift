import HFRModels
import SwiftUI

// Port of HFRswift/Swift/PollView.swift (PollToolbarButton, PollSheet, PollContentView, PollResultRow) and HFRswift/Swift/
// MessagesView.swift:4675-4680 (toolbar button) @ 2440d79. Differences: the button shows for a results poll too (legacy only for a
// poll not yet voted); the closed / already-voted notice HFR prints is shown; results bars use system colors (GAP-059).
/// The reader's poll entry (LOT-136): the "Sondage" toolbar button when the page has a poll, and the sheet.
struct ReaderPollFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's services; its voter is nil when logged out, which shows the poll without a vote button.
    let composer: ComposerServices?
    @State private var sheet: PollModel?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if model.page?.poll != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { sheet = model.pollModel(voter: composer?.pollVoter, account: composer?.account) } label: {
                            Label("Sondage", systemImage: "chart.bar.doc.horizontal")
                        }
                    }
                }
            }
            .sheet(item: $sheet) { poll in PollSheet(model: poll) }
    }
}

/// The poll: question, answers to choose or results, HFR's notice and total, and "Voter".
struct PollSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: PollModel

    var body: some View {
        ThemedNavigationStack {
            List {
                Section { Text(model.poll.question).font(.headline) }
                switch model.poll.kind {
                case .votable(let options, _): votingSection(options)
                case .results(let lines): resultsSection(lines)
                }
                if let notice = model.poll.notice { Section { Text(notice).font(.footnote).foregroundStyle(.secondary) } }
                if let footer = model.poll.footer { Section { Text(footer).font(.footnote).foregroundStyle(.secondary) } }
                if let message = model.message {
                    Section { Label(message, systemImage: icon).foregroundStyle(color) }
                        .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Sondage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.phase == .sending) }
                if model.offersVote {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Voter") { Task { await model.vote() } }.disabled(!model.canVote)
                    }
                }
            }
            .interactiveDismissDisabled(model.phase == .sending)
            .overlay { if model.phase == .sending { ProgressView().controlSize(.large) } }
        }
    }

    private var icon: String {
        switch model.phase {
        case .voted: "checkmark.circle.fill"
        case .settled: "info.circle.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch model.phase {
        case .voted: .green
        case .settled: .orange
        default: .red
        }
    }

    @ViewBuilder
    private func votingSection(_ options: [PollOption]) -> some View {
        Section {
            ForEach(options) { option in
                Button { model.toggle(option.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model.selected == option.id ? "circle.inset.filled" : "circle")
                            .foregroundStyle(model.selected == option.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .accessibilityHidden(true)
                        Text(option.text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!model.offersVote || model.phase == .sending)
                .accessibilityAddTraits(model.selected == option.id ? .isSelected : [])
            }
            if model.voterMissing {
                Text("Connectez-vous pour voter.").font(.footnote).foregroundStyle(.secondary)
            } else if model.poll.maxChoices > 1 {
                Text("Ce sondage à choix multiples n’est pas encore pris en charge : votez depuis le site.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ lines: [PollResult]) -> some View {
        Section {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.label)
                    ProgressView(value: min(max(line.percentage, 0), 100), total: 100)
                    Text("\(line.percentage.formatted(.number.precision(.fractionLength(1)))) % · \(votes(line.voteCount))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func votes(_ count: Int) -> String { count == 1 ? "1 vote" : "\(count) votes" }
}
