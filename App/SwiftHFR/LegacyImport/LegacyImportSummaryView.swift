import HFRStorage
import SwiftUI

// Port of none @ 87fe0d1c: legacy was the app this update replaces and never imported its data (GAP-170, new UX: spec).
/// The summary of the legacy import (LOT-158): what was taken over from the previous version, in counts, and a way to retry
/// what failed.
struct LegacyImportSummaryView: View {
    /// The summary the sheet opened with, shown until the model's own (refreshed by a retry) is read.
    let opened: LegacyImportSummary
    let model: LegacyImportModel
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let intro = "Vos données de l’ancienne version ont été reprises. Rien n’a été effacé, sauf l’ancien cache des pages."

    /// The model's summary, which a retry refreshes; the opening one once the sheet is closing.
    private var summary: LegacyImportSummary { model.summary ?? opened }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Self.intro).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(summary.rows) { row in
                        LabeledContent {
                            Text(row.detail)
                                .foregroundStyle(row.isFailure ? Color.orange : Color.secondary)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text(row.title)
                        }
                    }
                    if let rejected = summary.rejectedLine {
                        Text(rejected).foregroundStyle(.secondary)
                    }
                }
                if summary.canRetry {
                    Section {
                        Button("Réessayer", action: retry)
                            .disabled(model.isRunning)
                    }
                }
            }
            .navigationTitle("Import de HFR+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

extension LegacyImportSummary {
    /// A summary with an import, a retriable failure, a page-cache clean-up and a refused item, for previews.
    static var preview: LegacyImportSummary {
        var summary = LegacyImportSummary()
        summary.add(LegacyImportReport(
            outcomes: [
                .accounts: .imported(2), .pseudoLists: .imported(14), .drafts: .failed(.destinationFailed), .pageCache: .imported(37)
            ],
            rejectedItems: 1
        ))
        return summary
    }
}

#Preview {
    LegacyImportSummaryView(opened: .preview, model: .preview(), retry: {})
}
