import HFRModels

// Port of Classes/Forum.m (getImageFromID:) @ 87fe0d1c. Differences: keyed by the catalogue's category id, which the legacy
// URL table (`getImage`) mapped the same way (GAP-021).
/// The icon of a category of the Catégories list: the legacy image names, whose PNGs came from the legacy asset catalogue
/// (`SuperHFRplus/Assets/UI/`, @ 87fe0d1c; credit: [icons8](https://icons8.com/), `CREDITS.md`).
enum ForumCategoryIcon {
    /// Asset name for `category`; legacy's shield for a category it has no image for.
    static func assetName(for category: CategoryID?) -> String {
        guard case .forum(let number)? = category else { return "ShieldFilled-40" }
        return names[number] ?? "ShieldFilled-40"
    }

    private static let names: [Int: String] = [
        1: "ProcessorFilled-40", 16: "KeyboardFilled-40", 15: "LaptopFilled-40", 23: "SmartphoneTabletFilled-40",
        2: "SupportFilled-40", 30: "CircuitFilled-40", 25: "cat-apple", 3: "VideoCallFilled-40", 14: "CameraFilled-40",
        5: "ControllerFilled-40", 4: "WindowsClientFilled-40", 22: "Wi-FiLogoFilled-40", 21: "VOIPGatewayFilled-40",
        11: "Debian-40", 10: "SourceCodeFilled-40", 12: "DesignFilled-40", 6: "PriceTagUSDFilled-40",
        8: "GraduationCapFilled-40", 9: "BroadcastingFilled-40", 13: "ChatFilled-40", 24: "ChatFilled-40", 32: "AIFilled-40"
    ]
}
