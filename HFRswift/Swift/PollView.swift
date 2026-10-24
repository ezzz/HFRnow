//
//  PollView.swift
//  HFRswift
//
//  SwiftUI poll sheet: voting mode and results mode.
//

import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class PollViewModel {
    var pollData: PollData
    var selectedIndices: Set<Int> = []
    var isSubmitting = false
    var errorMessage: String?

    init(pollData: PollData) {
        self.pollData = pollData
    }

    var canSubmit: Bool {
        !selectedIndices.isEmpty && !isSubmitting && pollData.isVotable
    }

    func toggle(_ index: Int) {
        if pollData.maxChoices == 1 {
            // Single-choice: toggle selected or clear.
            selectedIndices = selectedIndices.contains(index) ? [] : [index]
        } else {
            // Multi-choice: add or remove, capped at maxChoices.
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else if selectedIndices.count < pollData.maxChoices {
                selectedIndices.insert(index)
            }
        }
    }

    func submitVote(onSuccess: @escaping @MainActor () -> Void) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let result = await PollVoteSubmitter.submit(pollData: pollData, selectedIndices: selectedIndices)

        isSubmitting = false
        switch result {
        case .success:
            onSuccess()
        case .error(let message):
            errorMessage = message
        }
    }
}

// MARK: - Toolbar button

struct PollToolbarButton: View {
    let isVotable: Bool
    let action: () -> Void

    var body: some View {
        if isVotable {
            Button("Sondage", systemImage: "chart.bar.fill", action: action)
                .hfrGlassButton(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        } else {
            Button("Sondage", systemImage: "chart.bar.fill", action: action)
                .hfrGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
    }
}

// MARK: - Sheet

struct PollSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pollData: PollData
    var onVoteSucceeded: (() -> Void)?

    @State private var viewModel: PollViewModel

    init(pollData: PollData, onVoteSucceeded: (() -> Void)? = nil) {
        self.pollData = pollData
        self.onVoteSucceeded = onVoteSucceeded
        self._viewModel = State(initialValue: PollViewModel(pollData: pollData))
    }

    var body: some View {
        NavigationStack {
            PollContentView(viewModel: viewModel) {
                Task {
                    await viewModel.submitVote {
                        dismiss()
                        onVoteSucceeded?()
                    }
                }
            }
            .navigationTitle("Sondage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        // Keep viewModel in sync if the sheet is presented with fresh data.
        .onChange(of: pollData.question) { _, _ in
            viewModel = PollViewModel(pollData: pollData)
        }
    }
}

// MARK: - Content view

/// Natif PollCard: surface card with eyebrow, question, 44 pt options or result bars, footer.
struct PollContentView: View {
    @Bindable var viewModel: PollViewModel
    var onVote: () -> Void = {}
    @Environment(\.natif) private var natif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sondage", systemImage: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(natif.text2)

                if !viewModel.pollData.question.isEmpty {
                    Text(viewModel.pollData.question)
                        .font(.headline)
                        .foregroundStyle(natif.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.pollData.isVotable {
                    votingContent
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.pollData.results) { result in
                            PollResultRow(result: result)
                        }
                    }
                }

                if !viewModel.pollData.footer.isEmpty {
                    Text(viewModel.pollData.footer)
                        .font(.footnote)
                        .foregroundStyle(natif.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(natif.surface, in: .rect(cornerRadius: 16))
            .padding(16)
        }
        .background(natif.bg)
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var votingContent: some View {
        if viewModel.pollData.maxChoices > 1 {
            Text("\(viewModel.pollData.maxChoices) choix possibles")
                .font(.subheadline)
                .foregroundStyle(natif.text2)
        }
        VStack(spacing: 0) {
            ForEach(Array(viewModel.pollData.options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Divider()
                }
                let isSelected = viewModel.selectedIndices.contains(option.id)
                Button {
                    viewModel.toggle(option.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName: viewModel.pollData.maxChoices == 1
                                ? (isSelected ? "largecircle.fill.circle" : "circle")
                                : (isSelected ? "checkmark.square.fill" : "square")
                        )
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? natif.accent : natif.text3)
                        Text(option.text)
                            .foregroundStyle(natif.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }

        Button(action: onVote) {
            Text(viewModel.isSubmitting ? "Envoi…" : "Voter")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(natif.accentFill))
                .opacity(viewModel.canSubmit || viewModel.isSubmitting ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit)
    }
}

// MARK: - Result row

/// 44 pt bar on surface2, filled proportionally in accentSoft, percentage on the right.
struct PollResultRow: View {
    let result: PollResult
    @Environment(\.natif) private var natif

    private var displayLabel: String {
        result.label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(displayLabel)
                .foregroundStyle(natif.text)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text("\(result.percentage.formatted(.number.precision(.fractionLength(0)))) %")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(natif.text)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(alignment: .leading) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    natif.surface2
                    natif.accentSoft
                        .frame(width: geo.size.width * min(max(result.percentage, 0), 100) / 100)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityValue(result.voteCount == 1 ? "1 vote" : "\(result.voteCount) votes")
    }
}

// MARK: - Previews

#Preview("Poll - voting") {
    PollSheet(pollData: PollData(
        question: "Quel est votre système d'exploitation préféré ?",
        footer: "Sondage créé le 01/01/2024 | 423 votes",
        maxChoices: 1,
        options: [
            PollOption(id: 1, text: "macOS", fieldName: "repone"),
            PollOption(id: 2, text: "Windows", fieldName: "repone"),
            PollOption(id: 3, text: "Linux", fieldName: "repone"),
        ],
        results: [],
        hiddenFields: ["post": "123", "cat": "456"]
    ))
}

#Preview("Poll - multi-choice") {
    PollSheet(pollData: PollData(
        question: "Quels langages utilisez-vous ?",
        footer: "",
        maxChoices: 3,
        options: [
            PollOption(id: 1, text: "Swift", fieldName: "rep1"),
            PollOption(id: 2, text: "Kotlin", fieldName: "rep2"),
            PollOption(id: 3, text: "Python", fieldName: "rep3"),
            PollOption(id: 4, text: "Rust", fieldName: "rep4"),
        ],
        results: [],
        hiddenFields: [:]
    ))
}

#Preview("Poll - results") {
    PollSheet(pollData: PollData(
        question: "Quel est votre système d'exploitation préféré ?",
        footer: "Sondage par ezzz le 01/01/2024 | 423 votes",
        maxChoices: 1,
        options: [],
        results: [
            PollResult(id: 1, label: "macOS", percentage: 44.9, voteCount: 190),
            PollResult(id: 2, label: "Windows", percentage: 38.1, voteCount: 161),
            PollResult(id: 3, label: "Linux", percentage: 17.0, voteCount: 72),
        ],
        hiddenFields: [:]
    ))
}
