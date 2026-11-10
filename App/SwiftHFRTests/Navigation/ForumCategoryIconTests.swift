import HFRModels
@testable import SwiftHFR
import Testing

struct ForumCategoryIconTests {
    // Legacy `Forum.m` `getImageFromID:` @ 87fe0d1c.
    @Test(arguments: [
        (1, "ProcessorFilled-40"), (16, "KeyboardFilled-40"), (15, "LaptopFilled-40"), (23, "SmartphoneTabletFilled-40"),
        (2, "SupportFilled-40"), (30, "CircuitFilled-40"), (25, "cat-apple"), (3, "VideoCallFilled-40"), (14, "CameraFilled-40"),
        (5, "ControllerFilled-40"), (4, "WindowsClientFilled-40"), (22, "Wi-FiLogoFilled-40"), (21, "VOIPGatewayFilled-40"),
        (11, "Debian-40"), (10, "SourceCodeFilled-40"), (12, "DesignFilled-40"), (6, "PriceTagUSDFilled-40"),
        (8, "GraduationCapFilled-40"), (9, "BroadcastingFilled-40"), (13, "ChatFilled-40"), (24, "ChatFilled-40"),
        (32, "AIFilled-40")
    ])
    func everyKnownCategoryHasItsLegacyIcon(id: Int, name: String) {
        #expect(ForumCategoryIcon.assetName(for: .forum(id)) == name)
    }

    @Test func anUnknownCategoryGetsLegacysShield() {
        #expect(ForumCategoryIcon.assetName(for: .forum(99)) == "ShieldFilled-40")
        #expect(ForumCategoryIcon.assetName(for: nil) == "ShieldFilled-40")
    }
}
