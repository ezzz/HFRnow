import Foundation
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift (ProfileFilterListEditorView: reloadProfiles, addProfile, removeProfiles, `:581-700`)
// and of Classes/BlackListTableViewController.m / WhiteListTableViewController.m (`addPseudoToList:`, delete row) @ 2440d79.
// Differences: the logic is a model over LOT-117's store (GAP-209); a list the store cannot read shows its failure and a retry
// instead of an empty list (writes are refused, the file is never overwritten); a pseudo already listed says so.
/// State of one list editor in Réglages (LOT-118): the sorted pseudos, the field for a manual add, and the errors.
@MainActor
@Observable
final class PseudoListEditorModel {
    let kind: PseudoListKind
    /// The pseudos of the list, sorted as legacy.
    private(set) var pseudos: [String] = []
    /// The text of the add field.
    var draft = ""
    /// The error of the last add or removal, for an alert; the view clears it.
    var errorMessage: String?
    /// Set when the stored lists cannot be read or written: the list shown is then not the stored one.
    private(set) var unreadableMessage: String?
    /// True once `load()` finished once, so the empty message does not flash before the first read.
    private(set) var hasLoaded = false

    @ObservationIgnored private let manager: PseudoListManager

    /// An editor of `kind` over `manager`.
    init(kind: PseudoListKind, manager: PseudoListManager) {
        self.kind = kind
        self.manager = manager
    }

    /// The blocklist needs an account: logged out, the editor explains it instead of showing an empty list.
    var requiresAccount: Bool { !manager.isAvailable(kind) }

    /// The pseudo in the field, cleaned (trimmed, zero-width characters out), as the store keeps it.
    var trimmedDraft: String {
        PseudoNormalizer.cleaned(draft).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The "Ajouter" button is enabled.
    var canAdd: Bool { !requiresAccount && unreadableMessage == nil && !trimmedDraft.isEmpty }

    /// Reads the list (on appear, after a retry). A store that cannot be read keeps the editor read-only.
    func load() async {
        if let failure = await manager.loadFailure() {
            unreadableMessage = Self.describe(failure)
            pseudos = []
        } else {
            unreadableMessage = nil
            pseudos = await manager.pseudos(of: kind)
        }
        hasLoaded = true
    }

    /// Reads the stored file again (the "Réessayer" button), for example after a restore.
    func retry() async {
        _ = await manager.reload()
        await load()
    }

    /// Adds the pseudo of the field. The field is emptied when the pseudo is listed afterwards, new or not.
    func add() async {
        let pseudo = trimmedDraft
        guard canAdd else { return }
        do {
            let added = try await manager.add(pseudo, to: kind)
            draft = ""
            if !added { errorMessage = "\(pseudo) est déjà dans la liste." }
        } catch {
            errorMessage = kind.addFailure
        }
        await load()
    }

    /// Removes `pseudo` (a swipe on its row). Removing the last entry leaves an empty list, saved like any other change.
    func remove(_ pseudo: String) async {
        do {
            try await manager.remove(pseudo, from: kind)
        } catch {
            errorMessage = kind.removeFailure(pseudo)
        }
        await load()
    }

    /// Removes the pseudos at `offsets` of the shown list.
    func remove(at offsets: IndexSet) async {
        let targets = offsets.compactMap { pseudos.indices.contains($0) ? pseudos[$0] : nil }
        for pseudo in targets { await remove(pseudo) }
    }

    private static func describe(_ error: PseudoListError) -> String {
        switch error {
        case .unsupportedVersion: "Ces listes viennent d'une version plus récente de l'app : elles ne sont pas modifiées."
        default: "Les listes enregistrées sont illisibles : elles ne sont pas modifiées."
        }
    }
}
