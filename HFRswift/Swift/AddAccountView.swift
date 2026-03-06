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

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Ajouter un pseudo")
                    .font(.title3)
                    .bold()

                VStack(spacing: 12) {
                    TextField("Pseudo", text: $pseudo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Mot de passe", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Valider")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
                .liquidGlassIfAvailable(in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground).opacity(0.85))
            )
            .liquidGlassIfAvailable(in: RoundedRectangle(cornerRadius: 24))
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
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
