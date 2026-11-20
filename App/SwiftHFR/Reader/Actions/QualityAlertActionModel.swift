import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
import Observation

// Port of HFRswift/Swift/MessagesView.swift (`askAQPrompt` `:4506-4543`, the AQ sheet `:5445-5473`, `isAQAlreadySignaled`
// `:325-340`, `createAQ` `:342-378`) @ 87fe0d1c. Differences: an AQ that someone else already raised is not refused: the member
// may add the message to it ("plussoyer", operator decision of 2026-11-07 on #224), and only their own report is "déjà signalé
// par vous"; the first-use notice N1 comes before the first POST (Q-4, LOT-071 T3); an answer the service did not confirm is
// checked against the topic's list before anything is said, never read as a refusal (LOT-055); the check is a typed list, not a
// substring test; no account, no entry. GAP-069.
/// « AQ » in the message menu (LOT-134): checks the topic's alerts, then, after the notice, creates an Alerte Qualitay on the
/// message or adds it to the one that exists. One per reader; no creation is sent before the notice N1 is accepted (the topic
/// check, T2, only says which topic is read).
@MainActor
@Observable
final class QualityAlertActionModel {
    /// Settings key of the first-use notice N1 (LOT-071): accepted once per device, like the Giphy and rehost ones.
    nonisolated static let noticeKey = "aq_notice_accepted"

    /// The message an alert is being raised for, and the alert it joins when there already is one.
    struct Draft: Equatable, Identifiable {
        let topic: TopicID
        let topicTitle: String
        let numreponse: Int
        let permalink: URL
        let author: String
        /// The AQ the message is added to ("plussoyer"); nil creates a new one.
        var existing: AQAlert?

        var id: String { "\(topic.topic)-\(numreponse)" }
    }

    /// What the reader asks next.
    enum Prompt: Equatable, Identifiable {
        /// The first-use notice, before the first creation; accepting goes on to the draft's own question.
        case notice(Draft)
        /// The title of a new AQ (legacy's prompt).
        case title(Draft)
        /// The question of adding the message to the AQ that holds it already.
        case addition(Draft)

        var id: String {
            switch self {
            case .notice(let draft): "notice-\(draft.id)"
            case .title(let draft): "title-\(draft.id)"
            case .addition(let draft): "addition-\(draft.id)"
            }
        }
    }

    /// What is asked now; the reader's views bind to it.
    var prompt: Prompt?
    /// A check or a send is running: a second pick waits.
    private(set) var isWorking = false

    @ObservationIgnored private let services: QualityAlertServices
    @ObservationIgnored private let topicTitle: @MainActor () -> String?
    @ObservationIgnored private let confirm: @MainActor (String) -> Void

    /// An AQ entry over `services`; `topicTitle` reads the title of the page on screen, `confirm` shows the outcome.
    init(
        services: QualityAlertServices, topicTitle: @escaping @MainActor () -> String?,
        confirm: @escaping @MainActor (String) -> Void
    ) {
        self.services = services
        self.topicTitle = topicTitle
        self.confirm = confirm
    }

    /// Nothing is asked or running: the model can be replaced by one with fresher services.
    var isIdle: Bool { prompt == nil && !isWorking }

    /// The notice N1 was accepted on this device.
    var isNoticeAccepted: Bool { services.settings.rawValue(forKey: Self.noticeKey) == .bool(true) }

    /// The text of notice N1: who runs the host, what is sent, what becomes public (LOT-071 T3, N1).
    var noticeMessage: String {
        QualityAlertMessages.notice(host: services.hostName)
    }

    /// The menu entry.
    var handler: any MessageActionHandler {
        QualityAlertActionHandler(
            canRun: { [weak self] in self?.canReport($0) ?? false },
            run: { [weak self] context in await self?.start(context) }
        )
    }

    /// Whether « AQ » is offered (legacy `canAQ`, `ObjCMessageActionsBuilder.m:19`: not in a private conversation): a public topic,
    /// a permalink to give the service and an account to report as (the service wants a pseudo).
    func canReport(_ context: MessageMenuContext) -> Bool {
        guard let topic = context.topic, topic.category != .privateMessages, context.permalinkURL != nil else { return false }
        return !services.pseudo.isEmpty
    }

    /// The picked entry: reads the topic's alerts, then asks what fits (a title, an addition) or says why nothing is asked.
    func start(_ context: MessageMenuContext) async {
        guard isIdle else { return }
        isWorking = true
        defer { isWorking = false }
        guard let topic = context.topic, let permalink = context.permalinkURL, let title = topicTitle(), !title.isEmpty else {
            confirm(QualityAlertMessages.incomplete)
            return
        }
        var draft = Draft(
            topic: topic, topicTitle: title, numreponse: context.numreponse, permalink: permalink, author: context.author
        )
        let alerts: [AQAlert]
        do throws(AQError) {
            alerts = try await services.service.alerts(topicID: topic.topic)
        } catch {
            // Legacy: no answer, no AQ (`MessagesView.swift:4531`); a refused or unreadable one is the same here.
            confirm(QualityAlertMessages.impossible)
            return
        }
        if let held = alerts.first(where: { $0.postIDs.contains(draft.numreponse) }) {
            if held.initiator.compare(services.pseudo, options: .caseInsensitive) == .orderedSame {
                confirm(QualityAlertMessages.ownReport)
                return
            }
            draft.existing = held
        }
        ask(next(for: draft))
    }

    /// The answer to the notice for `draft` (SwiftUI clears the alert's state before the button runs, LOT-087). Accepting is
    /// kept on this device and goes on to the draft's own question; declining creates nothing and records nothing.
    func answerNotice(_ accept: Bool, for draft: Draft) {
        prompt = nil
        guard accept else { return }
        services.settings.setRawValue(.bool(true), forKey: Self.noticeKey)
        prompt = next(for: draft)
    }

    /// Creates the AQ the member titled, or does nothing for a blank title.
    func create(_ draft: Draft, title: String) async {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        prompt = nil
        await send(draft, title: label)
    }

    /// Adds the message to the AQ that holds it already.
    func add(_ draft: Draft) async {
        guard let existing = draft.existing else { return }
        prompt = nil
        await send(draft, title: existing.title)
    }

    // MARK: - Implementation

    /// The question that follows the notice for `draft`.
    private func next(for draft: Draft) -> Prompt {
        draft.existing == nil ? .title(draft) : .addition(draft)
    }

    /// The notice first, whatever the draft, until it was accepted on this device.
    private func ask(_ question: Prompt) {
        switch question {
        case .title(let draft), .addition(let draft): prompt = isNoticeAccepted ? question : .notice(draft)
        case .notice: prompt = question
        }
    }

    private func send(_ draft: Draft, title: String) async {
        guard !isWorking else { return }
        // The gate itself, not only the sheets before it: no path sends before the notice was accepted.
        guard isNoticeAccepted else {
            prompt = .notice(draft)
            return
        }
        isWorking = true
        defer { isWorking = false }
        let report = AQNewReport(
            existingAlertID: draft.existing?.id, title: title, topicID: draft.topic.topic, topicTitle: draft.topicTitle,
            pseudo: services.pseudo, postID: draft.numreponse, postURL: draft.permalink, comment: "post de \(draft.author)"
        )
        do throws(AQCreateError) {
            try await services.service.create(report)
            confirm(draft.existing == nil ? QualityAlertMessages.created : QualityAlertMessages.added)
        } catch {
            await handle(failure: error, of: draft)
        }
    }

    private func handle(failure: AQCreateError, of draft: Draft) async {
        switch failure {
        case .cancelled:
            break
        case .invalidBaseURL:
            confirm(QualityAlertMessages.impossible)
        case .invalidReport(let problem):
            confirm(QualityAlertMessages.problem(problem))
        case .unconfirmed:
            // The POST may have been recorded and no answer is a refusal: read the topic's list before saying anything (LOT-055).
            switch await recorded(draft) {
            case true?: confirm(draft.existing == nil ? QualityAlertMessages.created : QualityAlertMessages.added)
            case false?: confirm(draft.existing == nil ? QualityAlertMessages.notRecorded : QualityAlertMessages.additionNotRecorded)
            case nil: confirm(QualityAlertMessages.unverified)
            }
        }
    }

    /// Whether the topic's list now holds the member's report of `draft`; nil when the list cannot be read.
    private func recorded(_ draft: Draft) async -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        guard let alerts = try? await services.service.alerts(topicID: draft.topic.topic) else { return nil }
        if let existing = draft.existing {
            // An addition repeats the message number in the AQ's list (`T02`: "47934539,47934539").
            let before = existing.postIDs.count { $0 == draft.numreponse }
            let after = alerts.first { $0.id == existing.id }?.postIDs.count { $0 == draft.numreponse } ?? 0
            return after > before
        }
        return alerts.contains {
            $0.postIDs.contains(draft.numreponse) && $0.initiator.compare(services.pseudo, options: .caseInsensitive) == .orderedSame
        }
    }
}

/// What the AQ entry needs of the service: the topic's alerts and a report. `AQClient` is the live one (LOT-055); the tests drive
/// the real client over a recorded transport.
protocol QualityAlertService: Sendable {
    /// The AQs already raised on a topic.
    func alerts(topicID: Int) async throws(AQError) -> [AQAlert]
    /// Reports a message: a new AQ, or an addition when the report names one.
    func create(_ report: AQNewReport) async throws(AQCreateError)
}

extension AQClient: QualityAlertService {}

/// The AQ entry's inputs for the current account (nil elsewhere: no entry).
struct QualityAlertServices: Sendable {
    /// The service the topic is checked and reported through.
    let service: any QualityAlertService
    /// Pseudo of the account reporting.
    let pseudo: String
    /// Host the reports go to, named in the notice.
    let hostName: String
    /// Where the accepted notice is kept (device scope).
    let settings: any SettingsStore
}

/// The entry of the message menu for an AQ (`MessageMenuAction.Kind.qualityAlert`).
@MainActor
struct QualityAlertActionHandler: MessageActionHandler {
    let canRun: @MainActor (MessageMenuContext) -> Bool
    let run: @MainActor (MessageMenuContext) async -> Void

    var kind: MessageMenuAction.Kind { .qualityAlert }

    func isAvailable(for context: MessageMenuContext) -> Bool { canRun(context) }

    func perform(with context: MessageMenuContext) async { await run(context) }
}

/// The words of the AQ entry, in French; legacy's where it had them (`MessagesView.swift:4514, 4531, 5463`).
enum QualityAlertMessages {
    static let incomplete = "Données AQ incomplètes"
    static let impossible = "Création d'AQ impossible"
    static let ownReport = "Post déjà signalé par vous"
    static let created = "Alerte Qualitay créée."
    static let added = "Message ajouté à l'Alerte Qualitay."
    /// No invitation to retry: every attempt e-mails the AQ operator and a refusal may be the anti-flood ban (HFR-PROTOCOL §8).
    static let notRecorded = "L'Alerte Qualitay n'a pas été enregistrée : le service a refusé ou n'a pas répondu."
    /// The topic's list does not say who joined an AQ: a refused addition is most often one the member already made (`T59`).
    static let additionNotRecorded =
        "Ajout non enregistré. Vous avez peut-être déjà signalé ce message dans cette alerte : vérifiez la liste avant de réessayer."
    static let unverified = "Alerte Qualitay non confirmée par le service. Vérifiez la liste avant de réessayer."

    /// The notice N1 (LOT-071 T3): the host and who runs it, what is sent, what becomes public, the operator's own records.
    static func notice(host: String) -> String {
        "Les Alertes Qualitay sont publiées sur \(host), un service communautaire qui n'est ni HFR ni cette application. "
            + "Pour créer ou plussoyer une alerte, l'application lui envoie, sans identification : votre pseudo (en minuscules), "
            + "le numéro et le titre du sujet, le numéro et le lien du message, le titre et le commentaire de l'alerte, et le nom "
            + "de l'application. L'alerte est publique. Le service garde une empreinte de votre adresse IP, dont une adresse IPv4 "
            + "peut être retrouvée, et prévient son exploitant par e-mail à chaque tentative, même refusée. Les conditions de cet "
            + "exploitant s'appliquent."
    }

    /// Why a report was refused before anything was sent.
    static func problem(_ problem: AQReportProblem) -> String {
        switch problem {
        case .missing(.title): "Donnez un titre à l'alerte."
        case .tooLong(.title): "Le titre de l'alerte est trop long."
        case .unsupportedCharacters: "Le titre ou le sujet contient un caractère que le service ne garde pas (la plupart des emoji)."
        case .tooLong, .missing, .outOfRange, .notForumPermalink: incomplete
        }
    }
}
