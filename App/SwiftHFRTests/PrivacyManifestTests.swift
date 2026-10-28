import Foundation
import Testing

/// LOT-160: the shipped bundle carries the privacy manifest and the Info.plist keys App Review checks.
struct PrivacyManifestTests {
    private func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func manifestIsInTheBundleAndDeclaresNoTracking() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    @Test func requiredReasonAPIsMatchWhatTheCodeUses() throws {
        let entries = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for entry in entries {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            reasons[category] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
        }
        // UserDefaults: HFRStorage settings store. File timestamps: HFRStorage cache eviction (app container).
        #expect(reasons == [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]
        ])
    }

    @Test func collectedDataIsNeverUsedForTracking() throws {
        let entries = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        var linking: [String: Bool] = [:]
        for entry in entries {
            let type = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            linking[type] = entry["NSPrivacyCollectedDataTypeLinked"] as? Bool
        }
        #expect(linking == [
            "NSPrivacyCollectedDataTypeUserID": true,
            "NSPrivacyCollectedDataTypeOtherUserContent": true,
            "NSPrivacyCollectedDataTypePhotosorVideos": false,
            "NSPrivacyCollectedDataTypeSearchHistory": false
        ])
        #expect(entries.allSatisfy { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == false })
        let functionality = ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        #expect(entries.allSatisfy { ($0["NSPrivacyCollectedDataTypePurposes"] as? [String]) == functionality })
    }

    @Test func infoPlistHasTheUsageStringsAndExportComplianceAnswer() throws {
        let info = try #require(Bundle.main.infoDictionary)
        for key in ["NSCameraUsageDescription", "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
            let text = try #require(info[key] as? String, "missing \(key)")
            #expect(!text.isEmpty)
        }
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }
}
