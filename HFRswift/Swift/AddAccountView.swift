//
//  AddAccountView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//

import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountsStore: AccountsStore

    @State private var pseudo = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    private var trimmedPseudo: String {
        pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var canSubmit: Bool {
        !isSubmitting && !trimmedPseudo.isEmpty && !password.isEmpty
    }

    @Environment(\.natif) private var natif
    @Environment(\.openURL) private var openURL
    @FocusState private var focusedField: Field?

    private enum Field {
        case pseudo
        case password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connectez-vous avec votre compte hardware.fr pour retrouver vos drapeaux, favoris et messages privés.")
                        .font(.subheadline)
                        .foregroundStyle(natif.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent {
                        TextField("Votre pseudo", text: $pseudo)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focusedField, equals: .pseudo)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    } label: {
                        Text("Pseudo").frame(width: 110, alignment: .leading)
                    }
                    LabeledContent {
                        SecureField("Requis", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    } label: {
                        Text("Mot de passe").frame(width: 110, alignment: .leading)
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(natif.destructive)
                    }
                }
                .natifCellBackground()

                Section {
                    Button(action: submit) {
                        Text("Se connecter")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(natif.accentFill))
                            .opacity(canSubmit || isSubmitting ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    VStack(spacing: 12) {
                        Text("Les identifiants sont stockés dans le trousseau iOS.")
                        Button("Créer un compte sur hardware.fr") {
                            if let url = URL(string: "https://forum.hardware.fr/inscription.php") {
                                openURL(url)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(natif.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                }
            }
            .natifGroupedListBackground()
            .navigationTitle("Ajouter un compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .onAppear { focusedField = .pseudo }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await accountsStore.addAccount(pseudo: trimmedPseudo, password: password)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
