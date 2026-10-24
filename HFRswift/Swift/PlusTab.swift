//
//  PlusTab.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import SwiftUI
import MessageUI

struct PlusHomeView: View {
    @ObservedObject var accountsStore: AccountsStore
    @State private var showDeleteAccountComposer = false
    @State private var showDeleteAccountConfirm = false
    @State private var showMailUnavailableAlert = false
    @State private var showAddAccountSheet = false
    @AppStorage(AQUnreadCounter.storageKey) private var unreadAQCount = 0
    @Environment(\.natif) private var natif

    var body: some View {
        List {
            Section {
                PlusAccountCard(accountsStore: accountsStore) {
                    showAddAccountSheet = true
                }
                .natifCellBackground()
            }

            Section("Forum") {
                NavigationLink {
                    ForumSearchView()
                } label: {
                    PlusRow(title: "Recherche sur le forum", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    BookmarksPlusView()
                } label: {
                    PlusRow(title: "Bookmarks", systemImage: "bookmark")
                }
                NavigationLink {
                    AQPlusView()
                } label: {
                    PlusRow(title: "Alertes Qualitay", systemImage: "megaphone", badgeCount: unreadAQCount)
                }
            }
            .natifCellBackground()

            Section("Application") {
                NavigationLink {
                    AppSettingsView()
                } label: {
                    PlusRow(title: "Réglages", systemImage: "gearshape")
                }
            }
            .natifCellBackground()

            Section("À propos") {
                NavigationLink {
                    StaticInfoPageView(kind: .charter)
                } label: {
                    PlusRow(title: "Charte du forum", systemImage: "book.closed")
                }
                NavigationLink {
                    StaticInfoPageView(kind: .credits)
                } label: {
                    PlusRow(title: "Crédits", systemImage: "heart")
                }
            }
            .natifCellBackground()

            Section {
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    Text("Supprimer mon compte")
                        .foregroundStyle(natif.destructive)
                        .frame(minHeight: 44)
                }
            } footer: {
                Text("Le compte HFR est supprimé côté forum. Cette action est irréversible.")
            }
            .natifCellBackground()
        }
        .listStyle(.insetGrouped)
        .natifGroupedListBackground()
        .navigationTitle("Plus")
        .rootSidebarRevealButton()
        .expandedPhoneInlineNavigationTitle()
        .confirmationDialog(
            "Supprimer votre compte HFR ?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Écrire la demande de suppression", role: .destructive) {
                if MFMailComposeViewController.canSendMail() {
                    showDeleteAccountComposer = true
                } else {
                    showMailUnavailableAlert = true
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La suppression est faite par l'équipe du forum, à partir d'un e-mail de demande.")
        }
        .sheet(isPresented: $showDeleteAccountComposer) {
            DeleteAccountMailComposeView()
        }
        .sheet(isPresented: $showAddAccountSheet) {
            AddAccountView(accountsStore: accountsStore)
        }
        .alert("Mail indisponible", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Aucun compte mail n'est configuré sur cet iPhone.")
        }
    }
}

/// Natif 3c account card: avatar 56, pseudo, account switcher.
private struct PlusAccountCard: View {
    @ObservedObject var accountsStore: AccountsStore
    let onAddAccount: () -> Void
    @Environment(\.natif) private var natif

    var body: some View {
        if let account = accountsStore.currentAccount {
            HStack(spacing: 14) {
                NatifAvatar(pseudo: account.displayName, image: account.avatarImage, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(natif.text)
                    Menu {
                        ForEach(accountsStore.accounts) { other in
                            Button {
                                accountsStore.setMain(other)
                            } label: {
                                if other.id == account.id {
                                    Label(other.displayName, systemImage: "checkmark")
                                } else {
                                    Text(other.displayName)
                                }
                            }
                        }
                        Divider()
                        Button(action: onAddAccount) {
                            Label("Ajouter un compte", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Text(accountsStore.accounts.count > 1
                             ? "Changer de compte · \(accountsStore.accounts.count) comptes"
                             : "Ajouter un compte")
                            .font(.subheadline)
                            .foregroundStyle(natif.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        } else {
            Button(action: onAddAccount) {
                HStack(spacing: 14) {
                    NatifAvatar(pseudo: nil, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Non connecté")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(natif.text)
                        Text("Se connecter")
                            .font(.subheadline)
                            .foregroundStyle(natif.accent)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PlusRow: View {
    let title: String
    let systemImage: String
    var badgeCount = 0
    @Environment(\.natif) private var natif

    var body: some View {
        HStack(spacing: 12) {
            NatifPictogram(systemImage: systemImage)
            Text(title)
                .foregroundStyle(natif.text)
            Spacer(minLength: 8)
            if badgeCount > 0 {
                NatifRedBadge(count: badgeCount)
                    .accessibilityLabel("\(badgeCount) nouvelles alertes")
            }
        }
        .frame(minHeight: 44)
    }
}

private struct DeleteAccountMailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject("Demande de suppression de compte")
        composer.setToRecipients(["marc@hardware.fr"])
        composer.setMessageBody(
            "Monsieur/Madame,\n\nJe vous écris pour vous demander de supprimer mon compte sur votre forum Hardware.fr. Je ne l'utilise plus et je préfère ne plus être membre de ce forum.\n\nSi vous avez besoin de plus d'informations pour traiter ma demande, veuillez me contacter à l'adresse email associée à mon compte.\n\nMerci d'avance pour votre aide.\n\nCordialement",
            isHTML: false
        )
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onDismiss()
        }
    }
}
