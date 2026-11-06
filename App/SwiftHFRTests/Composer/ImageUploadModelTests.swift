import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
import ImageIO
@testable import SwiftHFR
import Synchronization
import Testing
import UniformTypeIdentifiers

/// Answers each upload with the next scripted outcome and records the bytes it was given.
private final class ScriptedUploader: ImageUploading {
    private let state: Mutex<(outcomes: [Result<RehostedImage, RehostError>], received: [Data])>
    let gate: ReaderGate?

    init(_ outcomes: [Result<RehostedImage, RehostError>], gate: ReaderGate? = nil) {
        state = Mutex((outcomes, []))
        self.gate = gate
    }

    var received: [Data] { state.withLock { $0.received } }

    func upload(jpeg: Data) async throws(RehostError) -> RehostedImage {
        state.withLock { $0.received.append(jpeg) }
        if let gate { await gate.wait() }
        let outcome = state.withLock { state -> Result<RehostedImage, RehostError> in
            state.outcomes.isEmpty ? .failure(.invalidResponse) : state.outcomes.removeFirst()
        }
        return try outcome.get()
    }
}

/// A history kept in memory; `unreadable` makes `load` say so and every write throw, as the engine store does.
private final class MemoryHistory: ImageUploadHistoryStoring {
    private let state: Mutex<[RehostedImage]>
    private let unreadable: Bool
    private let failWrites: Bool

    init(_ images: [RehostedImage] = [], unreadable: Bool = false, failWrites: Bool = false) {
        state = Mutex(images)
        self.unreadable = unreadable
        self.failWrites = failWrites
    }

    var stored: [RehostedImage] { state.withLock { $0 } }

    func load() async -> (images: [RehostedImage], isUnreadable: Bool) { (unreadable ? [] : stored, unreadable) }

    func add(_ image: RehostedImage) async throws {
        if unreadable || failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        state.withLock { $0.insert(image, at: 0) }
    }

    func remove(id: String) async throws {
        if unreadable || failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        state.withLock { $0.removeAll { $0.id == id } }
    }
}

/// Counts what it is asked to prepare.
private final class RecordingPreparer: ImagePreparing {
    private let calls = Mutex(0)
    var callCount: Int { calls.withLock { $0 } }

    func prepare(_ source: Data, maxDimension: Int) throws(ImagePreparationError) -> Data {
        calls.withLock { $0 += 1 }
        return source
    }
}

/// Passes the bytes through, so a test can read what reached the uploader.
private struct PassThroughPreparer: ImagePreparing {
    func prepare(_ source: Data, maxDimension: Int) throws(ImagePreparationError) -> Data { source }
}

@MainActor
private final class IdleClipboard: ClipboardReading {
    var changeCount = 0
    var url: URL?
    var string: String?
}

private func hosted(_ name: String, at seconds: Double = 0) -> RehostedImage {
    RehostedImage(
        fullURL: url("https://img.example/images/\(name).jpg"), mediumURL: url("https://img.example/images/\(name).md.jpg"),
        miniURL: url("https://img.example/images/\(name).th.jpg"), width: 1200, height: 800,
        uploadedAt: Date(timeIntervalSince1970: seconds)
    )
}

@MainActor
private func make(
    uploader: (any ImageUploading)?, history: MemoryHistory = MemoryHistory(), accepted: Bool = false,
    preparer: any ImagePreparing = PassThroughPreparer()
) -> (ImageUploadModel, InMemorySettingsStore) {
    let settings = InMemorySettingsStore(accepted ? [ImageUploadModel.noticeKey: .bool(true)] : [:])
    let services = ImageUploadServices(
        uploader: uploader, hostName: "img.example", preparer: preparer, history: history, settings: settings
    )
    return (ImageUploadModel(services: services, now: { Date(timeIntervalSince1970: 7) }), settings)
}

/// Notice N1, the upload and its history (LOT-102).
@MainActor
struct ImageUploadModelTests {
    @Test func nothingIsPreparedOrSentBeforeTheNoticeIsAccepted() async {
        let uploader = ScriptedUploader([.success(hosted("a"))])
        let preparer = RecordingPreparer()
        let (model, settings) = make(uploader: uploader, preparer: preparer)
        await model.submit(Data([1, 2, 3]))
        #expect(model.isAskingNotice)
        #expect(uploader.received.isEmpty)
        #expect(preparer.callCount == 0)
        model.declineNotice()
        #expect(!model.isAskingNotice)
        #expect(uploader.received.isEmpty)
        #expect(preparer.callCount == 0)
        #expect(settings.rawValue(forKey: ImageUploadModel.noticeKey) == nil)
        await model.submit(Data([1, 2, 3]))
        #expect(model.isAskingNotice)
    }

    @Test func acceptingTheNoticeUploadsTheWaitingImageAndIsRemembered() async {
        let uploader = ScriptedUploader([.success(hosted("a")), .success(hosted("b"))])
        let (model, settings) = make(uploader: uploader)
        await model.submit(Data([1]))
        await model.acceptNotice()?.value
        #expect(uploader.received == [Data([1])])
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["a.jpg"])
        #expect(settings.rawValue(forKey: ImageUploadModel.noticeKey) == .bool(true))
        await model.submit(Data([2]))
        #expect(!model.isAskingNotice)
        #expect(uploader.received == [Data([1]), Data([2])])
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["b.jpg", "a.jpg"])
    }

    @Test func aBuildWithoutAKeySendsNothingAndSaysSo() async {
        let (model, _) = make(uploader: nil, accepted: true)
        await model.submit(Data([1]))
        #expect(!model.isAskingNotice)
        #expect(model.errorMessage == "L'envoi d'images n'est pas disponible dans cette version.")
        #expect(!model.canUpload)
    }

    @Test func aRefusalShowsTheHostsMessageAndRemembersNothing() async {
        let uploader = ScriptedUploader([.failure(.http(statusCode: 400, message: "Fichier trop lourd"))])
        let history = MemoryHistory()
        let (model, _) = make(uploader: uploader, history: history, accepted: true)
        await model.submit(Data([1]))
        #expect(model.errorMessage == "Erreur de l'hébergeur (400) : Fichier trop lourd")
        #expect(model.history.isEmpty)
        #expect(history.stored.isEmpty)
        #expect(!model.isUploading)
    }

    @Test func aLostAnswerIsNotRetriedAndAdmitsTheImageMayBeThere() async {
        let uploader = ScriptedUploader([.failure(.network(.timedOut))])
        let (model, _) = make(uploader: uploader, accepted: true)
        await model.submit(Data([1]))
        #expect(uploader.received.count == 1)
        #expect(model.errorMessage?.contains("peut-être été envoyée") == true)
    }

    @Test func aSecondPickWhileUploadingIsIgnored() async {
        let gate = ReaderGate()
        let uploader = ScriptedUploader([.success(hosted("a"))], gate: gate)
        let (model, _) = make(uploader: uploader, accepted: true)
        let first = Task { await model.submit(Data([1])) }
        await gate.untilArrived()
        #expect(model.isUploading)
        await model.submit(Data([2]))
        await gate.open()
        await first.value
        #expect(uploader.received == [Data([1])])
        #expect(!model.isUploading)
    }

    @Test func theHistoryIsSavedAndReadBackNewestFirst() async {
        let history = MemoryHistory([hosted("old", at: 1)])
        let (model, _) = make(uploader: ScriptedUploader([.success(hosted("new", at: 2))]), history: history, accepted: true)
        await model.load()
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["old.jpg"])
        await model.submit(Data([1]))
        #expect(history.stored.map(\.fullURL.lastPathComponent) == ["new.jpg", "old.jpg"])
        await model.remove(model.history[0])
        #expect(history.stored.map(\.fullURL.lastPathComponent) == ["old.jpg"])
    }

    @Test func askingToRemoveAnEntryChangesNothingUntilConfirmed() async {
        let history = MemoryHistory([hosted("a", at: 1), hosted("b", at: 2)])
        let (model, _) = make(uploader: nil, history: history)
        await model.load()
        model.requestRemoval(model.history[0])
        #expect(model.pendingRemoval?.fullURL.lastPathComponent == "b.jpg")
        #expect(model.history.count == 2)
        model.cancelRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(model.removalNotice == nil)
        #expect(history.stored.count == 2)
    }

    @Test func confirmingARemovalForgetsOnlyThatEntryAndSaysTheImageStaysOnline() async {
        let history = MemoryHistory([hosted("a", at: 1), hosted("b", at: 2)])
        let (model, _) = make(uploader: nil, history: history)
        await model.load()
        let target = model.history[0]
        model.requestRemoval(target)
        await model.confirmRemoval(target)
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["a.jpg"])
        #expect(history.stored.map(\.fullURL.lastPathComponent) == ["a.jpg"])
        #expect(model.pendingRemoval == nil)
        #expect(model.removalNotice?.contains("reste en ligne") == true)
        #expect(ImageUploadModel.removalMessage.contains("reste en ligne"))
    }

    @Test func aRemovalWhoseSaveFailsStillHidesTheEntryAndWarns() async {
        let history = MemoryHistory([hosted("a")], failWrites: true)
        let (model, _) = make(uploader: nil, history: history)
        await model.load()
        let target = model.history[0]
        await model.confirmRemoval(target)
        #expect(model.history.isEmpty)
        #expect(model.historyWarning == "L'historique des images n'a pas pu être enregistré.")
    }

    @Test func aKeptEntryStaysUsableAfterAnotherIsRemoved() async {
        let (model, _) = make(uploader: nil, history: MemoryHistory([hosted("keep", at: 1), hosted("drop", at: 2)]))
        await model.load()
        let drop = model.history[0]
        await model.confirmRemoval(drop)
        let kept = model.history[0]
        #expect(model.snippet(for: kept, variant: .full).contains("keep.jpg"))
        #expect(!model.history.contains { $0.id == drop.id })
    }

    @Test func anUnreadableHistoryIsNeverOverwrittenAndUploadsStillWork() async {
        let history = MemoryHistory([hosted("precious")], unreadable: true)
        let (model, _) = make(uploader: ScriptedUploader([.success(hosted("a"))]), history: history, accepted: true)
        await model.load()
        #expect(model.historyWarning?.contains("illisible") == true)
        await model.submit(Data([1]))
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["a.jpg"])
        #expect(history.stored.map(\.fullURL.lastPathComponent) == ["precious.jpg"])
        #expect(model.historyWarning == "L'historique des images n'a pas pu être enregistré.")
    }

    @Test func reopeningThePanelKeepsImagesThatCouldNotBeSaved() async {
        let (model, _) = make(
            uploader: ScriptedUploader([.success(hosted("a"))]), history: MemoryHistory(failWrites: true), accepted: true
        )
        await model.load()
        await model.submit(Data([1]))
        await model.load()
        #expect(model.history.map(\.fullURL.lastPathComponent) == ["a.jpg"])
    }

    @Test func settingsKeepTheirLegacyKeysAndDefaults() {
        let (model, settings) = make(uploader: nil)
        #expect(model.linkMode == .imageWithLink)
        #expect(model.maxDimension == .px1200)
        model.linkMode = .linkOnly
        model.maxDimension = .px600
        #expect(settings.rawValue(forKey: "rehost_use_link") == .int(2))
        #expect(settings.rawValue(forKey: "rehost_resize_before_upload") == .int(600))
    }

    @Test func theSnippetFollowsTheModeAndTheVariant() {
        let (model, _) = make(uploader: nil)
        let image = hosted("a")
        #expect(model.snippet(for: image, variant: .mini)
            == "[url=https://img.example/images/a.jpg][img]https://img.example/images/a.th.jpg[/img][/url]\n")
        model.linkMode = .imageNoLink
        #expect(model.snippet(for: image, variant: .medium) == "[img]https://img.example/images/a.md.jpg[/img]\n")
        model.linkMode = .linkOnly
        #expect(model.snippet(for: image, variant: .full) == "https://img.example/images/a.jpg")
    }

    @Test func aManualLinkNeedsAnHTTPURLWithAHost() {
        let (model, _) = make(uploader: nil)
        #expect(model.manualSnippet(for: " https://example.org/a.png ")
            == "[url=https://example.org/a.png][img]https://example.org/a.png[/img][/url]\n")
        for refused in ["", "example.org/a.png", "ftp://example.org/a.png", "javascript:alert(1)", "https://"] {
            #expect(model.manualSnippet(for: refused) == nil)
        }
    }

    @Test func theSnippetLandsAtTheCaretThroughTheComposersInsertion() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: "avant après")
        let formatting = ComposerFormattingModel(composer: composer, clipboard: IdleClipboard())
        formatting.selectedRange = NSRange(location: 6, length: 0)
        let (model, _) = make(uploader: nil)
        formatting.insert(model.snippet(for: hosted("a"), variant: .full))
        #expect(composer.text == "avant [url=https://img.example/images/a.jpg][img]https://img.example/images/a.jpg[/img][/url]\naprès")
    }

    @Test func theBuildSettingsMustBeRealValues() {
        let base = "https://img.example"
        #expect(ImageUploadServices.configuration(from: [:]) == nil)
        #expect(ImageUploadServices.configuration(from: ["RehostBaseURL": base, "RehostAPIKey": "$(REHOST_API_KEY)"]) == nil)
        #expect(ImageUploadServices.configuration(from: ["RehostBaseURL": "$(REHOST_BASE_URL)", "RehostAPIKey": "k"]) == nil)
        #expect(ImageUploadServices.configuration(from: ["RehostBaseURL": base, "RehostAPIKey": " "]) == nil)
        #expect(ImageUploadServices.configuration(from: ["RehostBaseURL": base, "RehostAPIKey": "k"]) != nil)
    }
}

/// What leaves the device: a re-encoded JPEG without metadata (LOT-071 T4, privacy note of #193).
@MainActor
struct ImageIOPreparerTests {
    /// A solid JPEG of `width` x `height` carrying GPS, EXIF and TIFF blocks and `orientation`.
    private func photo(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let writer = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.8566, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.3522, kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FakeCam", kCGImagePropertyTIFFModel: "X1"]
        ]
        CGImageDestinationAddImage(writer, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(writer))
        return output as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let reader = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(reader, 0, nil) as? [CFString: Any])
    }

    @Test func theFixtureReallyCarriesLocationAndTheOutputDoesNot() throws {
        let source = try photo(width: 300, height: 200)
        let before = try properties(source)
        #expect(before[kCGImagePropertyGPSDictionary] != nil)
        #expect(before[kCGImagePropertyExifDictionary] != nil)
        let output = try ImageIOPreparer().prepare(source, maxDimension: 1200)
        let after = try properties(output)
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        let tiff = after[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
        #expect((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect(output.range(of: Data("FakeCam".utf8)) == nil)
        #expect(output.range(of: Data("secret".utf8)) == nil)
    }

    @Test func theUploadedBodyHoldsNoLocationEndToEnd() async throws {
        let uploader = ScriptedUploader([.success(hosted("a"))])
        let (model, _) = make(uploader: uploader, accepted: true, preparer: ImageIOPreparer())
        await model.submit(try photo(width: 300, height: 200))
        let sent = try #require(uploader.received.first)
        #expect(try properties(sent)[kCGImagePropertyGPSDictionary] == nil)
        #expect(sent.range(of: Data("FakeCam".utf8)) == nil)
    }

    @Test func aLargeImageIsDownscaledToTheLongestSide() throws {
        let output = try ImageIOPreparer().prepare(try photo(width: 2000, height: 1000), maxDimension: 400)
        let after = try properties(output)
        #expect(after[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 200)
    }

    @Test func aSmallImageIsNeverUpscaled() throws {
        let output = try ImageIOPreparer().prepare(try photo(width: 300, height: 200), maxDimension: 1200)
        let after = try properties(output)
        #expect(after[kCGImagePropertyPixelWidth] as? Int == 300)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 200)
    }

    @Test func theOrientationIsAppliedBeforeTheMetadataIsDropped() throws {
        let output = try ImageIOPreparer().prepare(try photo(width: 300, height: 200, orientation: 6), maxDimension: 1200)
        let after = try properties(output)
        #expect(after[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 300)
    }

    @Test func bytesThatAreNotAnImageAreRefused() {
        #expect(throws: ImagePreparationError.unreadable) { try ImageIOPreparer().prepare(Data([1, 2, 3]), maxDimension: 800) }
    }
}
