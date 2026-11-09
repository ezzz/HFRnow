import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-155: the key and base URL come from the bundle (ADR 0007) and a build without a key hides the entry; media URLs stay on
/// Giphy's CDN. Fake keys only.
struct GifServicesTests {
    private static var info: [String: Any] { [GifServices.baseURLKey: "https://api.giphy.com", GifServices.apiKeyKey: "DUMMYKEY0123"] }

    /// A bundle on disk whose `Info.plist` is `info`, to read through `GifServices.live(bundle:)`.
    private static func bundle(_ info: [String: Any]) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appending(path: "gif-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: directory.appending(path: "Info.plist"))
        return try #require(Bundle(url: directory))
    }

    @Test func aKeyAndABaseUrlMakeTheConfiguration() throws {
        let configuration = try #require(GifServices.configuration(from: Self.info))
        #expect(configuration.baseURL.host() == "api.giphy.com")
    }

    @Test func aMissingBlankOrUnexpandedValueMeansNoFeature() {
        let blank = [GifServices.baseURLKey: "https://api.giphy.com", GifServices.apiKeyKey: "  "]
        let unexpandedKey = [GifServices.baseURLKey: "https://api.giphy.com", GifServices.apiKeyKey: "$(GIPHY_API_KEY)"]
        let unexpandedBase = [GifServices.baseURLKey: "$(GIPHY_BASE_URL)", GifServices.apiKeyKey: "DUMMYKEY0123"]
        let insecure = [GifServices.baseURLKey: "http://api.giphy.com", GifServices.apiKeyKey: "DUMMYKEY0123"]
        for info in [[:], blank, unexpandedKey, unexpandedBase, insecure] as [[String: Any]] {
            #expect(GifServices.configuration(from: info) == nil)
        }
    }

    @Test func theLiveServicesReadTheBundleAndAreAvailableOnlyWithAKey() throws {
        let withKey = GifServices.live(bundle: try Self.bundle(Self.info))
        #expect(withKey.isAvailable)
        #expect(withKey.hostName == "api.giphy.com")

        let blank = [GifServices.baseURLKey: "https://api.giphy.com", GifServices.apiKeyKey: ""]
        let blankKey = GifServices.live(bundle: try Self.bundle(blank))
        #expect(!blankKey.isAvailable)
        #expect(blankKey.hostName == nil)
        #expect(!GifServices.live(bundle: try Self.bundle([:])).isAvailable)
    }

    @Test func onlyHttpsGiphyHostsAreAllowed() throws {
        let allowed = ["https://media3.giphy.com/media/x/giphy.gif?cid=1", "https://giphy.com/gifs/x", "https://MEDIA.GIPHY.COM/a.gif"]
        let refused = [
            "http://media3.giphy.com/a.gif", "https://evil.example/a.gif", "https://giphy.com.evil.example/a.gif",
            "https://notgiphy.com/a.gif", "https://user:pw@media3.giphy.com/a.gif", "ftp://media3.giphy.com/a.gif", "https:///a.gif"
        ]
        for text in allowed { #expect(GifMediaPolicy.isAllowed(try #require(URL(string: text))), "\(text)") }
        for text in refused { #expect(!GifMediaPolicy.isAllowed(try #require(URL(string: text))), "\(text)") }
    }
}
