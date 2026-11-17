import HFRStorage

extension MPCheckInterval {
    /// Picker label (operator, 2026-11-07 on #230).
    var title: String {
        switch self {
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 h"
        case .twoHours: "2 h"
        case .fourHours: "4 h"
        case .never: "Jamais"
        }
    }

    /// The footer under the picker: the interval is a minimum, iOS picks the real moment (operator's text).
    var footer: String {
        switch self {
        case .never: "Aucune vérification en arrière-plan."
        case .oneHour: "Au plus souvent toutes les heures. " + Self.systemDecides
        default: "Au plus souvent toutes les \(title). " + Self.systemDecides
        }
    }

    private static let systemDecides = "iOS décide du moment réel ; ce délai est un minimum, pas une garantie."
}
