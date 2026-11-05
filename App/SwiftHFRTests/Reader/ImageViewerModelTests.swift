import Foundation
@testable import SwiftHFR
import Testing

/// Records what the viewer asked its services for.
private actor Recorder {
    private(set) var loads: [String] = []
    func record(_ url: URL) { loads.append(url.absoluteString) }
}

/// What the pasteboard service received.
@MainActor
private final class CopyLog {
    var urls: [URL] = []
}

/// The viewer's state: what it downloads, falls back to, saves and copies (LOT-109). No test waits on a clock: `settle()` is the signal.
@MainActor
struct ImageViewerModelTests {
    private static let bytes = ViewerImage(data: Data([1, 2, 3]), mimeType: "image/png")

    private func images(_ count: Int) -> [GalleryImage] {
        (0..<count).compactMap { number in
            guard let shown = URL(string: "https://reho.st/thumb/\(number).jpg"),
                  let full = URL(string: "https://reho.st/\(number).jpg") else { return nil }
            return GalleryImage(shown: shown, full: full, allowsThirdParty: true)
        }
    }

    private func services(
        recorder: Recorder = Recorder(), failing: Set<String> = [],
        save: @escaping @Sendable (ViewerImage) async throws(ImageSaveError) -> Void = { _ in },
        copy: @escaping @MainActor @Sendable (URL) -> Void = { _ in }
    ) -> ImageViewerServices {
        ImageViewerServices(
            load: { url, _ in
                await recorder.record(url)
                if failing.contains(url.absoluteString) { throw URLError(.badServerResponse) }
                return Self.bytes
            },
            save: save, copy: copy
        )
    }

    @Test func onlyTheSelectedImageAndItsNeighboursAreRequested() async {
        let recorder = Recorder()
        let model = ImageViewerModel(images: images(6), index: 2, services: services(recorder: recorder))
        model.prefetch()
        await model.settle()
        #expect(Set(await recorder.loads) == ["https://reho.st/1.jpg", "https://reho.st/2.jpg", "https://reho.st/3.jpg"])
        #expect(model.states[2] == .loaded(Self.bytes))
        #expect(model.states[5] == .idle)
    }

    @Test func swipingRequestsTheNewNeighbourOnce() async {
        let recorder = Recorder()
        let model = ImageViewerModel(images: images(6), index: 0, services: services(recorder: recorder))
        model.prefetch()
        await model.settle()
        model.index = 1
        await model.settle()
        model.index = 0
        await model.settle()
        let loads = await recorder.loads
        #expect(loads.sorted() == ["https://reho.st/0.jpg", "https://reho.st/1.jpg", "https://reho.st/2.jpg"])
    }

    @Test func aMissingFullSizeImageFallsBackToTheThumbnailTheUserSaw() async {
        let recorder = Recorder()
        let model = ImageViewerModel(
            images: images(1), index: 0, services: services(recorder: recorder, failing: ["https://reho.st/0.jpg"])
        )
        model.prefetch()
        await model.settle()
        #expect(await recorder.loads == ["https://reho.st/0.jpg", "https://reho.st/thumb/0.jpg"])
        #expect(model.states[0] == .loaded(Self.bytes))
        // The link copied is the one that answered, not the dead full-size address.
        #expect(model.currentLink?.absoluteString == "https://reho.st/thumb/0.jpg")
    }

    @Test func anImageWhoseEveryURLFailsCanBeRetried() async {
        let model = ImageViewerModel(
            images: images(1), index: 0,
            services: services(failing: ["https://reho.st/0.jpg", "https://reho.st/thumb/0.jpg"])
        )
        model.prefetch()
        await model.settle()
        #expect(model.states[0] == .failed)
        model.retry(0)
        #expect(model.states[0] == .loading)
        await model.settle()
        #expect(model.states[0] == .failed)
    }

    @Test func imagesFarFromTheSelectedOneAreDroppedFromMemory() async {
        let model = ImageViewerModel(images: images(6), index: 0, services: services())
        model.prefetch()
        await model.settle()
        for position in 1...4 {
            model.index = position
            await model.settle()
        }
        #expect(model.states[0] == .idle)
        #expect(model.states[1] == .idle)
        #expect(model.states[3] == .loaded(Self.bytes))
        #expect(model.states[4] == .loaded(Self.bytes))
        #expect(model.states[5] == .loaded(Self.bytes))
    }

    @Test func closingTheViewerLeavesNoImageStuckOnTheSpinner() {
        let model = ImageViewerModel(images: images(2), index: 0, services: services())
        model.prefetch()
        #expect(model.states == [.loading, .loading])
        model.cancel()
        #expect(model.states == [.idle, .idle])
    }

    @Test func copyLinkCopiesTheFullSizeAddress() {
        let log = CopyLog()
        let model = ImageViewerModel(images: images(2), index: 1, services: services(copy: { log.urls.append($0) }))
        model.copyLink()
        #expect(log.urls.map(\.absoluteString) == ["https://reho.st/1.jpg"])
        #expect(model.feedback == "Lien copié")
    }

    @Test func saveSendsTheDownloadedBytesAndSaysSo() async {
        let saved = Recorder()
        let model = ImageViewerModel(
            images: images(1), index: 0, services: services(save: { _ in await saved.record(URL(string: "x:saved")!) })
        )
        await model.saveToPhotos()
        #expect(model.feedback == "Image pas encore chargée")
        #expect(await saved.loads.isEmpty)
        model.prefetch()
        await model.settle()
        await model.saveToPhotos()
        #expect(model.feedback == "Photo enregistrée")
        #expect(await saved.loads == ["x:saved"])
    }

    @Test func everySaveFailureHasItsOwnMessage() async {
        let cases: [(ImageSaveError, String)] = [
            (.permissionDenied, "Autorise l'accès aux Photos pour enregistrer l'image."),
            (.invalidImage, "Impossible d'enregistrer cette image."),
            (.system, "L'enregistrement dans Photos a échoué.")
        ]
        for (error, text) in cases {
            let failing: @Sendable (ViewerImage) async throws(ImageSaveError) -> Void = { _ async throws(ImageSaveError) in
                throw error
            }
            let model = ImageViewerModel(images: images(1), index: 0, services: services(save: failing))
            model.prefetch()
            await model.settle()
            await model.saveToPhotos()
            #expect(model.feedback == text)
        }
    }

    @Test func theIndexIsClampedAndASingleImageShowsNoPosition() {
        let model = ImageViewerModel(images: images(3), index: 9, services: services())
        #expect(model.index == 2)
        #expect(model.positionText == "3 / 3")
        #expect(ImageViewerModel(images: images(1), index: 0, services: services()).positionText.isEmpty)
    }
}
