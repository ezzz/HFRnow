//
//  PlusTab.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import SwiftUI
import MessageUI

struct PlusHomeView: View {
    @State private var showDeleteAccountComposer = false
    @State private var showMailUnavailableAlert = false
    @AppStorage(AQUnreadCounter.storageKey) private var unreadAQCount = 0

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AppSettingsView()
                } label: {
                    PlusRow(title: "Réglages", systemImage: "gearshape")
                }

                NavigationLink {
                    ForumSearchView()
                } label: {
                    PlusRow(title: "Rechercher sur le forum", systemImage: "magnifyingglass")
                }

                NavigationLink {
                    BookmarksPlusView()
                } label: {
                    PlusRow(title: "Bookmarks", systemImage: "pin")
                }

                NavigationLink {
                    AQPlusView()
                } label: {
                    PlusRow(title: "Alertes Qualitay", systemImage: "bell", badgeCount: unreadAQCount)
                }

                NavigationLink {
                    StaticInfoPageView(kind: .credits)
                } label: {
                    PlusRow(title: "Crédits", systemImage: "info.circle")
                }

                NavigationLink {
                    StaticInfoPageView(kind: .charter)
                } label: {
                    PlusRow(title: "Charte du forum", systemImage: "doc.text")
                }

                Button(role: .destructive) {
                    if MFMailComposeViewController.canSendMail() {
                        showDeleteAccountComposer = true
                    } else {
                        showMailUnavailableAlert = true
                    }
                } label: {
                    PlusRow(title: "Supprimer mon compte", systemImage: "trash", foregroundStyle: .red)
                }
            }
        }
        .navigationTitle("Plus")
        .sheet(isPresented: $showDeleteAccountComposer) {
            DeleteAccountMailComposeView()
        }
        .alert("Mail indisponible", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Aucun compte mail n'est configuré sur cet iPhone.")
        }
    }
}

private struct PlusRow: View {
    let title: String
    let systemImage: String
    var badgeCount = 0
    var foregroundStyle: Color = .primary

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(foregroundStyle)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(foregroundStyle)
            }
            Spacer()
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .accessibilityLabel("\(badgeCount) nouvelles alertes")
            }
        }
        .padding(.vertical, 11)
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
