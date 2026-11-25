import SwiftUI

// Port of HFRswift/Swift/AddAccountView.swift (AddAccountView) @ 2440d79. Differences: AutoFill; the login is validated in a fresh
// session first (LOT-043, GAP-161).
/// The login sheet: pseudo and password, adapted from legacy `HFRswift/Swift/AddAccountView.swift`.
struct LoginView: View {
    /// Where the form is shown (#1176, HIG › Sheets: one sheet at a time). The main interface presents it as a sheet; inside the
    /// Comptes sheet it is pushed on that sheet's stack, so closing it lands on the account list, not on another sheet.
    enum Presentation: Sendable, Equatable {
        case sheet
        case pushed

        /// A sheet brings its own navigation stack; a pushed form uses the one it was pushed on.
        var wrapsInNavigationStack: Bool { self == .sheet }
        /// « Annuler » closes the sheet; a pushed form has the system back button, and leaving cancels the login.
        var offersCancelButton: Bool { self == .sheet }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var model: LoginModel
    @FocusState private var focusedField: Field?
    private let presentation: Presentation

    private enum Field {
        case pseudo, password
    }

    /// Creates the sheet for `target`.
    init(target: LoginTarget, accounts: AccountsModel, presentation: Presentation = .sheet) {
        self.presentation = presentation
        _model = State(initialValue: LoginModel(target: target, accounts: accounts))
    }

    var body: some View {
        LoginStack(presentation: presentation) {
            Form {
                Section {
                    Group {
                        TextField("Pseudo", text: $model.pseudo)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(!model.canEditPseudo)
                            .focused($focusedField, equals: .pseudo)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                        SecureField("Mot de passe", text: $model.password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { model.submit() }
                    }.themedListRow()
                } footer: {
                    Group {
                        if case .existing = model.target {
                            Text("Saisissez le mot de passe de ce compte pour renouveler sa session.")
                        }
                    }.themedSectionHeader()
                }

                if let message = model.errorMessage {
                    Section {
                        StatusLabel(text: message, symbol: "exclamationmark.triangle.fill", tint: .red).themedListRow()
                    }
                }

                Section {
                    Group {
                        Button {
                            model.submit()
                        } label: {
                            HStack {
                                Spacer()
                                if model.isSubmitting {
                                    ProgressView().accessibilityLabel("Connexion en cours")
                                } else {
                                    Text("Se connecter").bold()
                                }
                                Spacer()
                            }
                        }
                        .disabled(!model.canSubmit)
                    }.themedListRow()
                }
            }
            .navigationTitle(model.canEditPseudo ? "Ajouter un compte" : "Se reconnecter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentation.offersCancelButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            model.cancel()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { focusedField = model.canEditPseudo ? .pseudo : .password }
            .onChange(of: model.didSucceed) { _, succeeded in
                if succeeded { dismiss() }
            }
            .onChange(of: model.errorMessage) { _, message in
                // The message appears below the focused field: VoiceOver would not reach it unprompted.
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
            .onDisappear { model.cancel() }
        }
    }
}

/// The login form's container: its own stack as a sheet, none when pushed on another stack (a nested stack would draw two bars).
private struct LoginStack<Content: View>: View {
    let presentation: LoginView.Presentation
    @ViewBuilder var content: Content

    var body: some View {
        if presentation.wrapsInNavigationStack {
            ThemedNavigationStack { content }
        } else {
            content.appScreenBackground()
        }
    }
}
