import HFRModels
import SwiftUI

/// The bubble of the « Bouton + » info button: the three choices, one verified sentence each, the default marked (#1062).
struct ReplyButtonInfoView: View {
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(ReplyButtonBehavior.allCases, id: \.self) { behavior in
                VStack(alignment: .leading) {
                    Text(behavior.isDefault ? "\(behavior.title) (par défaut)" : behavior.title)
                        .bold()
                    Text(behavior.explanation)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }
}
