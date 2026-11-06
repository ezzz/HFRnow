import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

// Port of HFRswift/Swift/AnswerView.swift (ReplyImageInsertionView, startImageUpload :646-676) and HFRswift/Swift/ReplyService.swift
// (RehostPreferences, RehostPreferencesStore, RehostUploadedImage.formattedSnippet) @ 2440d79
// (GAP-090, GAP-091). Differences: the first-use
// notice N1 (LOT-071) gates every upload; the upload client is the engine's `RehostClient` (LOT-056); the preview rendition does not
// exist in the engine (`RehostedImage` has full, medium and mini); a failed upload never loses the composer text (it is not touched).
/// State of the image panel of the composer (LOT-102): the pick, the notice, the upload, the history and the settings.
///
/// The panel only produces a snippet: inserting it at the caret is the composer's (`ComposerFormattingModel.insert`).
@MainActor
@Observable
final class ImageUploadModel {
    /// Settings key of the first-use notice N1 (LOT-071): accepted once per device.
    nonisolated static let noticeKey = "rehost_notice_accepted"

    /// An upload (prepare, send) is running.
    private(set) var isUploading = false
    /// Why the last upload or pick failed, in French; nil when there is nothing to report.
    private(set) var errorMessage: String?
    /// The history could not be read or written; uploads stay usable.
    private(set) var historyWarning: String?
    /// Uploaded images, newest first.
    private(set) var history: [RehostedImage] = []
    /// A picked image waits for the notice: nothing is prepared or sent until it is accepted.
    private(set) var pendingSource: Data?
    /// The history entry the user asked to forget; it stays until the removal is confirmed (LOT-103).
    private(set) var pendingRemoval: RehostedImage?
    /// What the last removal did, in French; says the image is still online. Cleared by the next request, upload or reopening.
    private(set) var removalNotice: String?

    /// How a snippet is written (legacy `rehost_use_link`, kept under its legacy key).
    var linkMode: RehostLinkMode { didSet { services.settings.set(linkMode, for: SettingKey.rehostLinkMode) } }
    /// Longest side after downscaling (legacy `rehost_resize_before_upload`).
    var maxDimension: RehostMaxDimension { didSet { services.settings.set(maxDimension, for: SettingKey.rehostMaxDimension) } }

    private var didLoad = false
    private let services: ImageUploadServices
    private let now: @Sendable () -> Date

    /// A panel over `services`; `now` dates a manual link.
    init(services: ImageUploadServices, now: @escaping @Sendable () -> Date = { Date() }) {
        self.services = services
        self.now = now
        linkMode = services.settings.value(for: SettingKey.rehostLinkMode)
        maxDimension = services.settings.value(for: SettingKey.rehostMaxDimension)
    }

    /// This build can upload (a key was injected).
    var canUpload: Bool { services.uploader != nil }

    /// The notice N1 was accepted on this device.
    var isNoticeAccepted: Bool { services.settings.rawValue(forKey: Self.noticeKey) == .bool(true) }

    /// The notice N1 is on screen.
    var isAskingNotice: Bool { pendingSource != nil }

    /// The text of notice N1: who runs the host, what is sent, that the result is public (LOT-071 T4).
    var noticeMessage: String {
        let host = services.hostName ?? "l'hébergeur d'images"
        return "Les images sont envoyées à \(host), un service communautaire qui n'est ni HFR ni cette application. "
            + "Sont envoyés : l'image, recompressée et réduite à la dimension choisie, sans ses métadonnées (dont la position), "
            + "sans votre pseudo ni vos cookies. L'image devient publique et ne peut pas être supprimée depuis l'application. "
            + "Les conditions de l'hébergeur s'appliquent."
    }

    /// Reads the remembered uploads, once per model: reopening the panel keeps what is in memory. Unreadable data is never overwritten.
    func load() async {
        removalNotice = nil
        guard !didLoad else { return }
        didLoad = true
        let stored = await services.history.load()
        let known = Set(history.map(\.id))
        history += stored.images.filter { !known.contains($0.id) }
        history.sort { $0.uploadedAt > $1.uploadedAt }
        if stored.isUnreadable {
            historyWarning = "L'historique des images est illisible : les nouvelles images ne seront pas enregistrées."
        }
    }

    /// A picked image: asks the notice first if it was never accepted, else uploads. Nothing leaves before the notice.
    func submit(_ source: Data) async {
        guard !isUploading, !isAskingNotice else { return }
        errorMessage = nil
        removalNotice = nil
        guard canUpload else {
            errorMessage = Self.message(for: .notConfigured)
            return
        }
        guard isNoticeAccepted else {
            pendingSource = source
            return
        }
        await upload(source)
    }

    /// The user accepted the notice: it is remembered at once (so the alert closes) and the waiting image goes up in the
    /// returned task.
    @discardableResult
    func acceptNotice() -> Task<Void, Never>? {
        guard let source = pendingSource else { return nil }
        pendingSource = nil
        // Exception recorded in the spec: `SettingKey` is the legacy catalogue (its tests pin it), N1's flag is new.
        services.settings.setRawValue(.bool(true), forKey: Self.noticeKey)
        return Task { await upload(source) }
    }

    /// The user refused the notice: the image is dropped, nothing was sent and the notice will ask again.
    func declineNotice() {
        pendingSource = nil
    }

    /// The picker or the camera gave nothing usable.
    func pickFailed() {
        errorMessage = "Impossible de lire cette image."
    }

    /// The text to insert for `image`, in the chosen mode.
    func snippet(for image: RehostedImage, variant: RehostImageVariant) -> String {
        image.snippet(variant: variant, mode: Self.mode(linkMode))
    }

    /// The text for a link typed by hand (legacy "URL manuelle": the full rendition), nil unless it is an `http(s)` URL with a host.
    func manualSnippet(for text: String) -> String? {
        guard let url = Self.manualURL(text) else { return nil }
        return RehostedImage(fullURL: url, uploadedAt: now()).snippet(variant: .full, mode: Self.mode(linkMode))
    }

    /// The removal confirmation (LOT-103, FEAT-019): only the local entry goes, the image stays public on the host. No server-side
    /// delete is evidenced (HFR-PROTOCOL §7b B12), so the app never claims one.
    static let removalMessage =
        "Seule l'entrée de cet historique est effacée. L'image reste en ligne et publique chez l'hébergeur, son adresse reste valable."

    /// Notice shown after a removal.
    static let removedNotice = "Entrée retirée de l'historique. L'image reste en ligne chez l'hébergeur."

    /// The user swiped an entry: asks for confirmation, nothing is removed yet.
    func requestRemoval(_ image: RehostedImage) {
        removalNotice = nil
        pendingRemoval = image
    }

    /// The user backed out of the confirmation.
    func cancelRemoval() {
        pendingRemoval = nil
    }

    /// The user confirmed `image` (the entry the dialog was shown for: SwiftUI clears its state before the button runs): forgets it,
    /// then says the image stays online.
    func confirmRemoval(_ image: RehostedImage) async {
        pendingRemoval = nil
        history.removeAll { $0.id == image.id }
        // Set before the write is awaited: a request or upload arriving meanwhile clears it, a late write must not set it again.
        removalNotice = Self.removedNotice
        await persist { try await $0.remove(id: image.id) }
        if historyWarning == Self.saveWarning { removalNotice = nil }
    }

    private func upload(_ source: Data) async {
        guard let uploader = services.uploader else { return }
        isUploading = true
        defer { isUploading = false }
        let preparer = services.preparer
        let dimension = maxDimension.rawValue
        do {
            let jpeg = try await Task.detached { try preparer.prepare(source, maxDimension: dimension) }.value
            let image = try await uploader.upload(jpeg: jpeg)
            history.removeAll { $0.id == image.id }
            history.insert(image, at: 0)
            await persist { try await $0.add(image) }
        } catch let error as RehostError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Impossible de préparer cette image."
        }
    }

    /// Runs one write of the store; a refusal leaves the list in memory and says so.
    private func persist(_ write: (any ImageUploadHistoryStoring) async throws -> Void) async {
        do {
            try await write(services.history)
            if historyWarning == Self.saveWarning { historyWarning = nil }
        } catch {
            historyWarning = Self.saveWarning
        }
    }

    private static let saveWarning = "L'historique des images n'a pas pu être enregistré."

    private static func mode(_ mode: RehostLinkMode) -> RehostBBCodeMode {
        RehostBBCodeMode(rawValue: mode.rawValue) ?? .imageWithLink
    }

    /// An absolute `http(s)` URL with a host, trimmed.
    static func manualURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host()?.isEmpty == false else { return nil }
        return url
    }

    /// The French sentence of a failed upload; the host's own message is kept (it is already cut and cleared of the key).
    nonisolated static func message(for error: RehostError) -> String {
        switch error {
        case .notConfigured, .invalidBaseURL: "L'envoi d'images n'est pas disponible dans cette version."
        case .emptyImage: "Impossible de préparer cette image."
        case .network(.cancelled): "Envoi annulé."
        case .network(.offline): "Pas de connexion : l'image n'a pas été envoyée."
        case .network(.timedOut): "Délai dépassé : l'image a peut-être été envoyée, l'application n'en a pas la confirmation."
        case .network: "La connexion a échoué : l'image a peut-être été envoyée, l'application n'en a pas la confirmation."
        case .http(let code, let message), .rejected(let code, let message):
            message.map { "Erreur de l'hébergeur (\(code)) : \($0)" } ?? "Erreur de l'hébergeur (\(code))."
        case .invalidResponse: "Réponse illisible de l'hébergeur."
        case .missingImageURL: "L'hébergeur n'a pas renvoyé l'adresse de l'image."
        }
    }
}
