import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the progress "Chargement de l'alerte...", `:5368-5375`; the composer sheet,
// `:5497-5505`; the alerts "Alerter les modérateurs par email ?" and "Alerte impossible", `:5534-5546`) @ 87fe0d1c.
// Differences: GAP-070; "Alerte non confirmée" for an alert that may have left.
/// The screens of "Alerter" (LOT-135), all driven by `ModeratorAlertModel`. No branch on `alerts`: it arrives after the first
/// render, and a branch would rebuild the reader's web view.
struct ReaderAlertFlow: ViewModifier {
    let alerts: ModeratorAlertModel?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress = alerts?.progress {
                    ProgressView(progress).padding().glassEffect(in: .rect(cornerRadius: 12))
                }
            }
            .sheet(item: Binding(get: { alerts?.composer }, set: { alerts?.composer = $0 })) { composer in
                ModeratorAlertComposerView(model: composer).presentationDetents([.large])
            }
            .alert(
                "Alerter les modérateurs par email ?",
                isPresented: Binding(get: { alerts?.pendingMail != nil }, set: { if !$0 { alerts?.pendingMail = nil } }),
                presenting: alerts?.pendingMail
            ) { mail in
                Button("Non", role: .cancel) {}
                Button("Oui") { alerts?.confirmMail(mail) }
            } message: { _ in
                Text("Un email sera préparé dans votre application Mail.")
            }
            .alert(
                alerts?.failure?.title ?? "",
                isPresented: Binding(get: { alerts?.failure != nil }, set: { if !$0 { alerts?.failure = nil } }),
                presenting: alerts?.failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }
}
