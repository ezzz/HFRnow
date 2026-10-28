import Foundation
import Observation

/// State of the login form: fields, submission, error text. The view only binds to it.
@MainActor
@Observable
final class LoginModel {
    /// Pseudo typed by the user; fixed for a re-login.
    var pseudo: String
    /// Password typed by the user; kept in memory only, cleared once the login succeeds, never stored.
    var password = ""
    /// What the last attempt failed with, ready to show; nil when there is nothing to show.
    private(set) var errorMessage: String?
    /// True while a login runs.
    private(set) var isSubmitting = false
    /// True once the account is logged in and stored: the view dismisses itself.
    private(set) var didSucceed = false

    /// Which account the form logs in.
    let target: LoginTarget

    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Creates the form for `target`.
    init(target: LoginTarget, accounts: AccountsModel) {
        self.target = target
        self.accounts = accounts
        if case .existing(_, let displayName) = target {
            pseudo = displayName
        } else {
            pseudo = ""
        }
    }

    /// The pseudo field is editable only for a new account.
    var canEditPseudo: Bool { target == .newAccount }

    /// Both fields are filled and no attempt runs (legacy `AddAccountView.swift:23-25`).
    var canSubmit: Bool {
        !isSubmitting && !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    /// Starts a login; ignored while one runs or when a field is empty.
    func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let pseudo = pseudo
        let password = password
        task = Task { await run(pseudo: pseudo, password: password) }
    }

    /// Waits for the running attempt (tests).
    func waitForSubmission() async {
        await task?.value
    }

    /// Cancels a running attempt (the sheet was dismissed); the session is left as it was (LOT-043).
    func cancel() {
        task?.cancel()
    }

    private func run(pseudo: String, password: String) async {
        do {
            try await accounts.logIn(pseudo: pseudo, password: password, for: target)
            self.password = ""
            didSucceed = true
        } catch {
            errorMessage = AccountMessages.message(for: error)
        }
        isSubmitting = false
        task = nil
    }
}
