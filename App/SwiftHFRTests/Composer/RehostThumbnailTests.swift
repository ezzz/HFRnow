import Foundation
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1193: the image panel's history and the composer's chips load their thumbnails through the cookie-less image client and its
/// policy, never `AsyncImage` (`URLSession.shared`), and only from the configured rehost host.
struct RehostThumbnailTests {
    private static let host = "img.example"

    /// A transport that answers every request with a non-image body: the test only counts what was asked.
    private func transport() -> MockTransport {
        MockTransport { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 200, url: request.url, body: Data("not an image".utf8))
        }
    }

    /// A thumbnail on another host is never requested, nor one whose host is only a suffix match.
    @Test(arguments: [
        "https://other.example/images/a.th.jpg", "https://evil.img.example.attacker.test/a.th.jpg",
        "https://xn--img-example.test/a.th.jpg", "file:///etc/hosts"
    ])
    func anOffHostThumbnailSendsNoRequest(_ address: String) async throws {
        let transport = transport()
        let loader = SmileyImageLoader.rehostThumbnails(host: Self.host, fetcher: ReaderImageFetcher(transport: transport))
        let image = await loader.image(at: try #require(URL(string: address)))
        #expect(image == nil)
        #expect(await transport.requests.isEmpty)
    }

    /// The configured host is asked through the cookie-less client, over https even for an `http` history entry.
    @Test func anOnHostThumbnailIsRequestedOverHTTPS() async throws {
        let transport = transport()
        let loader = SmileyImageLoader.rehostThumbnails(host: Self.host, fetcher: ReaderImageFetcher(transport: transport))
        _ = await loader.image(at: try #require(URL(string: "http://IMG.example/images/2026/01/01/b.th.jpg")))
        let requests = await transport.requests
        #expect(requests.map(\.url.absoluteString) == ["https://IMG.example/images/2026/01/01/b.th.jpg"])
    }

    /// A redirect off the host stops there.
    @Test func aRedirectOffTheHostIsNotFollowed() async throws {
        let transport = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 302, headers: ["Location": "https://other.example/x.jpg"], url: request.url)
        }
        let loader = SmileyImageLoader.rehostThumbnails(host: Self.host, fetcher: ReaderImageFetcher(transport: transport))
        _ = await loader.image(at: try #require(URL(string: "https://img.example/images/c.th.jpg")))
        #expect(await transport.requests.map(\.url.host) == ["img.example"])
    }

    /// Without a configured host (no rehost key in the build), no thumbnail is requested at all.
    @Test func withoutAHostNothingIsRequested() async throws {
        let transport = transport()
        let loader = SmileyImageLoader.rehostThumbnails(host: nil, fetcher: ReaderImageFetcher(transport: transport))
        _ = await loader.image(at: try #require(URL(string: "https://img.example/images/d.th.jpg")))
        #expect(await transport.requests.isEmpty)
    }

    private func services(hostName: String?, configuredHost: String? = nil) -> ImageUploadServices {
        ImageUploadServices(
            uploader: nil, hostName: hostName, preparer: ImageIOPreparer(),
            history: LiveImageUploadHistory(store: RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence())),
            settings: InMemorySettingsStore(), configuredHost: configuredHost
        )
    }

    /// The chips and the history load through the services' own loader: an off-host thumbnail sends nothing, an on-host one
    /// is asked.
    @Test func theServicesLoaderAsksOnlyTheirHost() async throws {
        let transport = transport()
        let loader = services(hostName: Self.host).thumbnails(fetcher: ReaderImageFetcher(transport: transport))
        _ = await loader.image(at: try #require(URL(string: "https://other.example/images/e.th.jpg")))
        #expect(await transport.requests.isEmpty)
        _ = await loader.image(at: try #require(URL(string: "https://img.example/images/e.th.jpg")))
        #expect(await transport.requests.map(\.url.host) == ["img.example"])
    }

    /// #1249: the loader the history and the chips read (the model's) keeps the rehost host filter: off-host refused,
    /// on-host allowed (a loader without a filter, or Giphy's, fails this).
    @MainActor
    @Test func thePanelsLoaderFiltersOnTheRehostHost() throws {
        let model = ImageUploadModel(services: services(hostName: Self.host))
        let filter = try #require(model.thumbnails.hostFilter)
        #expect(filter(try #require(URL(string: "https://img.example/images/g.th.jpg"))))
        #expect(!filter(try #require(URL(string: "https://other.example/images/g.th.jpg"))))
        #expect(!filter(try #require(URL(string: "https://media.giphy.com/media/g/giphy.gif"))))
    }

    /// A build without a key still shows the thumbnails of an imported or synced history, from the configured base URL's
    /// host only; without that either, nothing is asked.
    @Test func aKeylessBuildUsesTheConfiguredBaseHost() async throws {
        #expect(ImageUploadServices.baseHost(from: ["RehostBaseURL": "https://img.example", "RehostAPIKey": ""]) == Self.host)
        #expect(ImageUploadServices.baseHost(from: ["RehostBaseURL": "$(REHOST_BASE_URL)"]) == nil)
        #expect(ImageUploadServices.baseHost(from: ["RehostBaseURL": " "]) == nil)
        #expect(ImageUploadServices.baseHost(from: [:]) == nil)
        let transport = transport()
        let loader = services(hostName: nil, configuredHost: Self.host).thumbnails(fetcher: ReaderImageFetcher(transport: transport))
        _ = await loader.image(at: try #require(URL(string: "https://other.example/images/f.th.jpg")))
        _ = await loader.image(at: try #require(URL(string: "https://img.example/images/f.th.jpg")))
        #expect(await transport.requests.map(\.url.host) == ["img.example"])
    }
}

/// Every image the app requests goes through `ReaderImageFetcher`: no `AsyncImage` and no `URLSession.shared` in app code
/// (comments may name them).
struct ImageLoadingConventionTests {
    @Test func appCodeLoadsNoImageOutsideTheImageClient() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SwiftHFR")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var count = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            count += 1
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                if code.contains("AsyncImage(") || code.contains("URLSession.shared") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(count > 100)
        #expect(offenders.isEmpty)
    }
}
