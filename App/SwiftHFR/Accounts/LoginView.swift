import SwiftUI

/// The login sheet: pseudo and password, adapted from legacy `HFRswift/Swift/AddAccountView.swift`.
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LoginModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case pseudo, password
    }

    /// Creates the sheet for `target`.
    init(target: LoginTarget, accounts: AccountsModel) {
        _model = State(initialValue: LoginModel(target: target, accounts: accounts))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } footer: {
                    if case .existing = model.target {
                        Text("Saisissez le mot de passe de ce compte pour renouveler sa session.")
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        model.submit()
                    } label: {
                        HStack {
                            Spacer()
                            if model.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Se connecter").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
            .navigationTitle(model.canEditPseudo ? "Ajouter un compte" : "Se reconnecter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear { focusedField = model.canEditPseudo ? .pseudo : .password }
            .onChange(of: model.didSucceed) { _, succeeded in
                if succeeded { dismiss() }
            }
            .onDisappear { model.cancel() }
        }
    }
}
