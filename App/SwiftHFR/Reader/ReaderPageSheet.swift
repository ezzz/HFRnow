import SwiftUI

/// The rules of the "Page numéro" sheet, apart from the view so they are tested as they are.
enum ReaderPagePicker {
    /// Legacy's fixed 260 pt stop (`Common.swift:3212` @ 87fe0d1c) stays the first one and is where the sheet opens; `.medium` lets
    /// the member drag it taller when Dynamic Type makes the field and the two button rows taller than that, and the content
    /// scrolls meanwhile (#1167, HIG › Typography).
    static let detents: Set<PresentationDetent> = [.height(260), .medium]

    /// One quick button of the sheet's second row.
    enum Step: Int, CaseIterable {
        case minusTen = -10, minusOne = -1, plusOne = 1, plusTen = 10

        /// Legacy's button titles, in legacy's order.
        var title: String {
            switch self {
            case .minusTen: "-10"
            case .minusOne: "-1"
            case .plusOne: "+1"
            case .plusTen: "+10"
            }
        }

        /// Legacy's VoiceOver labels.
        var accessibilityLabel: String {
            switch self {
            case .minusTen: "Dix pages en moins"
            case .minusOne: "Une page en moins"
            case .plusOne: "Une page en plus"
            case .plusTen: "Dix pages en plus"
            }
        }
    }

    /// `page` held in 1…`maxPage`.
    static func clamped(_ page: Int, maxPage: Int) -> Int {
        min(max(page, 1), max(maxPage, 1))
    }

    /// The field's text as a page: a number out of range is held in range, text that is no number reads as page 1
    /// (legacy `resolvedPage`).
    static func resolved(_ input: String, maxPage: Int) -> Int {
        clamped(Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, maxPage: maxPage)
    }

    /// The field after a step button: the resolved page moved by the step, held in range (legacy `offsetPage`).
    static func stepped(_ input: String, by step: Step, maxPage: Int) -> String {
        "\(clamped(resolved(input, maxPage: maxPage) + step.rawValue, maxPage: maxPage))"
    }

    /// What "Valider" opens: nil while the field is not a page of the topic (legacy `isInputValid`, which disables the button).
    static func target(_ input: String, maxPage: Int) -> Int? {
        guard let page = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)), (1...max(maxPage, 1)).contains(page) else {
            return nil
        }
        return page
    }
}

// Port of HFRswift/Swift/Common.swift (TopicPagePickerSheet, TopicPagePickerQuickButton) @ 87fe0d1c (lines 3063-3190).
// Differences: the quick buttons use the system tint, not `themePalette.actionTintColor` / `.systemGray3` (GAP-060, follow-up
// in the PR's issue list). The field opens on the current page, as legacy does (`Common.swift:3532` @ 87fe0d1c). A second
// detent and a scrolling content for large text sizes, which legacy's fixed 260 pt lacks (#1167).
/// The "Page numéro" sheet: first | number | last, then -10 | -1 | +1 | +10, "Valider" opens the page.
struct ReaderPageSheet: View {
    let maxPage: Int
    let onSubmit: (Int) -> Void
    @State private var input: String
    @Environment(\.dismiss) private var dismiss

    init(currentPage: Int, maxPage: Int, onSubmit: @escaping (Int) -> Void) {
        self.maxPage = maxPage
        self.onSubmit = onSubmit
        _input = State(initialValue: "\(ReaderPagePicker.clamped(currentPage, maxPage: maxPage))")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choisir une page entre 1 et \(maxPage)").font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        quickButton(systemImage: "backward.end", label: "Première page") { input = "1" }
                        TextField("1...\(maxPage)", text: $input)
                            .keyboardType(.numberPad)
                            .font(.body.monospacedDigit())
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                        quickButton(systemImage: "forward.end", label: "Dernière page") { input = "\(maxPage)" }
                    }
                    HStack(spacing: 10) {
                        ForEach(ReaderPagePicker.Step.allCases, id: \.self) { step in
                            quickButton(title: step.title, label: step.accessibilityLabel) {
                                input = ReaderPagePicker.stepped(input, by: step, maxPage: maxPage)
                            }
                        }
                    }
                }
                .padding(20)
            }
            // The sheet opens at 260 pt as legacy's; at a large text size the member can drag it taller and the content
            // scrolls meanwhile (#1167).
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Page numéro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Valider") {
                        if let page = ReaderPagePicker.target(input, maxPage: maxPage) {
                            onSubmit(page)
                            dismiss()
                        }
                    }
                    .disabled(ReaderPagePicker.target(input, maxPage: maxPage) == nil)
                }
            }
        }
        .presentationDetents(ReaderPagePicker.detents)
        .presentationDragIndicator(.visible)
    }

    private func quickButton(
        title: String? = nil, systemImage: String? = nil, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}
