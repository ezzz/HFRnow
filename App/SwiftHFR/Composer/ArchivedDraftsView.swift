import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (ReplyDraftPickerSheet, :1855-2001) @ 87fe0d1c. Differences: a navigation stack instead of
// the hand-drawn header; the list is the model's (per account, LOT-063); GAP-093. #1107: the list look of every list (`listLook`).
// #1179: « Vider » asks first (legacy deleted at once, `:1936-1941`); GAP-093.
/// The picker of a topic's archived drafts (LOT-101): "Mettre de côté et vider", the list, swipe "Supprimer", "Vider".
struct ArchivedDraftsView: View {
    let model: ReplyComposerModel
    /// Called after a draft was picked or the text set aside: the sheet closes and the editor takes focus.
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// "Vider" asks first (#1179); nothing is deleted before the confirmation is accepted.
    @State private var clearing = ArchivedClearConfirmation()

    var body: some View {
        ThemedNavigationStack {
            Group {
                if model.archivedDrafts.isEmpty && !model.canArchiveCurrent {
                    ContentUnavailableView(
                        "Aucun brouillon", systemImage: "tray", description: Text("Les brouillons sont conservés par topic.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Brouillons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbarItem { dismiss() }
                ToolbarItem(placement: .primaryAction) {
                    Button("Vider", role: .destructive) { clearing.request() }
                        .disabled(model.archivedDrafts.isEmpty || model.isMovingDrafts)
                        .confirmationDialog(
                            ArchivedDraftsFormat.clearConfirmQuestion, isPresented: $clearing.isAsking, titleVisibility: .visible
                        ) {
                            Button(ArchivedDraftsFormat.clearConfirmTitle, role: .destructive) {
                                Task { await clearing.confirm(discardingIn: model) }
                            }
                            Button("Annuler", role: .cancel) { clearing.cancel() }
                        } message: {
                            Text(ArchivedDraftsFormat.clearConfirmMessage(count: model.archivedDrafts.count))
                        }
                }
            }
        }
    }

    private var list: some View {
        List {
            // #1107: every row of the list takes its look, once for the whole content.
            Group {
                if model.canArchiveCurrent {
                    Section {
                        Button { Task { await model.archiveAndClear(); onDone() } } label: {
                            Label("Mettre de côté et vider", systemImage: "tray.and.arrow.down")
                        }
                        .densityRowMargin()
                    }
                }
                Section {
                    if model.archivedDrafts.isEmpty {
                        Text("Aucun brouillon archivé").foregroundStyle(.secondary).densityRowMargin()
                    } else {
                        ForEach(model.archivedDrafts) { draft in
                            Button { Task { await model.use(draft); onDone() } } label: { row(draft).themedRowText() }
                                .buttonStyle(.plain)
                                .densityRowMargin()
                                .disabled(model.isMovingDrafts)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                                        Task { await model.discardArchived(draft) }
                                    }
                                }
                        }
                    }
                }
            }
            .listLookRows()
        }
        .listLook()
    }

    private func row(_ draft: ArchivedDraft) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(ArchivedDraftsFormat.title(of: draft.source)).scaledFont(.subheadline).fontWeight(.semibold)
                Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(ArchivedDraftsFormat.dateLabel(of: draft.archivedAt)).scaledFont(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            Text(ArchivedDraftsFormat.preview(of: draft.text)).scaledFont(.body).lineLimit(2)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
