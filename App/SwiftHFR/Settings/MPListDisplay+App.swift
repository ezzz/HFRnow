import HFRModels

extension MPListDisplay {
    /// Picker label (LOT-171).
    var title: String {
        switch self {
        case .single: "Tout en un"
        case .split: "Deux listes"
        }
    }
}
