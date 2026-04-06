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
            Button("Sondage", systemImage: "chart.bar.doc.horizontal", action: action)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        } else {
            Button("Sondage", systemImage: "chart.bar.doc.horizontal", action: action)
                .buttonStyle(.bordered)
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
            PollContentView(viewModel: viewModel)
                .navigationTitle("Sondage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                    if viewModel.pollData.isVotable {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Voter") {
                                Task {
                                    await viewModel.submitVote {
                                        dismiss()
                                        onVoteSucceeded?()
                                    }
                                }
                            }
                            .disabled(!viewModel.canSubmit)
                        }
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

struct PollContentView: View {
    @Bindable var viewModel: PollViewModel

    var body: some View {
        List {
            if !viewModel.pollData.question.isEmpty {
                Section {
                    Text(viewModel.pollData.question)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if viewModel.pollData.isVotable {
                votingSection
            } else {
                resultsSection
            }

            if !viewModel.pollData.footer.isEmpty {
                Section {
                    Text(viewModel.pollData.footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isSubmitting {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
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
    private var votingSection: some View {
        Section {
            if viewModel.pollData.maxChoices > 1 {
                Text("\(viewModel.pollData.maxChoices) choix possibles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.pollData.options) { option in
                Button {
                    viewModel.toggle(option.id)
                } label: {
                    HStack(spacing: 12) {
                        let isSelected = viewModel.selectedIndices.contains(option.id)
                        Image(
                            systemName: viewModel.pollData.maxChoices == 1
                                ? (isSelected ? "circle.inset.filled" : "circle")
                                : (isSelected ? "checkmark.square.fill" : "square")
                        )
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .imageScale(.large)

                        Text("\(option.id). \(option.text)")
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            ForEach(viewModel.pollData.results) { result in
                PollResultRow(result: result)
            }
        }
    }
}

// MARK: - Result row

struct PollResultRow: View {
    let result: PollResult

    private var displayLabel: String {
        result.label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayLabel)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.tint.opacity(0.15))
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(geo.size.width * result.percentage / 100.0, result.percentage > 0 ? 4 : 0))
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)

                Text("\(result.percentage.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)

                Text(result.voteCount == 1 ? "1 vote" : "\(result.voteCount) votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
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
