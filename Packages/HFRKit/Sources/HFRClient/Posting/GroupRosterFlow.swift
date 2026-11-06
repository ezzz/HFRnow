import Foundation
import HFRModels
import HFRNetwork

/// Changes the members of a group private thread through its owner's reply (LOT-058, captures `W74`-`W77`).
///
/// HFR has no roster request: the composer's `newdest` input is edited and the reply is posted, with its ordinary answer.
/// So a change always posts `text`. The flow refuses locally what HFR could not take back or would read otherwise (see
/// `GroupRosterError`), then checks the session (LOT-044, #314), sends one POST and never retries it, like any other write.
/// HFR's order and a change of several members at once are not captured: the roster is read again from the composer after
/// a success, never assumed from what was sent.
public struct GroupRosterFlow: Sendable {
    /// What the change asks before it leaves: the health of the account session, from one GET of HFR (LOT-044).
    typealias SessionCheck = () async throws(NetworkError) -> SessionHealth

    /// The fewest other members a group can keep: with one, the composer stops serving `newdest` (`W72`, `R124`).
    static let minimumMembers = 2

    private let refresh: SessionRefreshFlow
    private let flow = PostingFlow()

    /// Creates the flow.
    public init() {
        self.init(refresh: SessionRefreshFlow())
    }

    /// A flow whose session check is `refresh` (tests: a refresh flow with scripted probes).
    init(refresh: SessionRefreshFlow) {
        self.refresh = refresh
    }

    /// Replies with `text` through the owner's composer `form`, its `newdest` being `members`: every member but the owner,
    /// as `PostingForm.groupMembers` lists them. Names are trimmed; blanks and repeated names are dropped.
    ///
    /// `session` is the session that loaded `form`; it is checked first (one GET of the profile page).
    /// - Throws: `rosterNotOffered`, `emptyRoster`, `tooFewMembers`, `namesOwner`, `invalidMemberName`,
    ///   `sessionNotConfirmed`, `posting`.
    public func changeMembers(
        to members: [String], text: String, options: [PostOption: Bool] = [:], with form: PostingForm, in session: HFRSession
    ) async throws(GroupRosterError) -> GroupRosterChange {
        guard form.session === session else { throw .posting(.sessionChanged) }
        let refresh = self.refresh
        let check: SessionCheck = { () async throws(NetworkError) -> SessionHealth in try await refresh.refresh(session) }
        return try await changeMembers(to: members, text: text, options: options, with: form, after: check)
    }

    // MARK: - Steps

    /// `changeMembers`, sent only when `check` says the account session is valid; a refused roster or text asks nothing.
    func changeMembers(
        to members: [String], text: String, options: [PostOption: Bool], with form: PostingForm, after check: SessionCheck
    ) async throws(GroupRosterError) -> GroupRosterChange {
        let roster = try Self.roster(members, for: form)
        do throws(PostingError) {
            try flow.checkText(text)
        } catch {
            throw .posting(error)
        }
        try await Self.confirm(check)
        let result: PostingResult
        do throws(PostingError) {
            let overrides = [PostingForm.groupMembersField: roster]
            result = try await flow.submit(.reply, form: form, text: text, overrides: overrides, options: options)
        } catch {
            throw .posting(error)
        }
        return GroupRosterChange(posting: result, members: await reloadedMembers(of: form))
    }

    /// The `newdest` value of `members`, joined as HFR serves it and as the captured edits sent it (", ", `W74`, `W75`).
    static func roster(_ members: [String], for form: PostingForm) throws(GroupRosterError) -> String {
        guard form.shape == .reply, form.isPrivateThread, form.groupMembers != nil else { throw .rosterNotOffered }
        var seen: Set<String> = []
        let names = members.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !names.isEmpty else { throw .emptyRoster }
        // Checked before counting: "a, b" is two members for HFR, "a" and "a," only one.
        guard names.allSatisfy(isSendable) else { throw .invalidMemberName }
        if let owner = form.form.field(named: "pseudo")?.value, seen.contains(owner.lowercased()) { throw .namesOwner }
        guard names.count >= minimumMembers else { throw .tooFewMembers(minimum: minimumMembers) }
        return names.joined(separator: ", ")
    }

    private static func isSendable(_ name: String) -> Bool {
        !name.contains(",") && !name.contains(where: \.isNewline) && PostCharacterCheck.truncatingCharacters(in: name).isEmpty
    }

    /// Lets the POST leave only after a `valid` session check; a check that could not be done is a `network` failure.
    private static func confirm(_ check: SessionCheck) async throws(GroupRosterError) {
        if Task.isCancelled { throw .posting(.network(.cancelled)) }
        let health: SessionHealth
        do throws(NetworkError) {
            health = try await check()
        } catch {
            throw .posting(.network(error))
        }
        guard health == .valid else { throw .sessionNotConfirmed(health) }
    }

    /// The change is confirmed whatever this read gives: a failure leaves the roster unknown, not the write undone.
    private func reloadedMembers(of form: PostingForm) async -> [String]? {
        try? await flow.loadForm(at: form.pageURL, through: form.session).groupMembers
    }
}
