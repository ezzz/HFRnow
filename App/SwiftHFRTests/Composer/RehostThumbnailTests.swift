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

    /// The panel's services hand the loader the host they upload to.
    @Test func theServicesFilterOnTheirHost() {
        let services = ImageUploadServices(
            uploader: nil, hostName: Self.host, preparer: ImageIOPreparer(), history: LiveImageUploadHistory(
                store: RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence())
            ),
            settings: InMemorySettingsStore()
        )
        #expect(services.thumbnailHost == Self.host)
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
