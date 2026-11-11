import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// One uploaded image in the panel's history; writes are not used here.
private struct OneImageHistory: ImageUploadHistoryStoring {
    let image: RehostedImage
    func load() async -> (images: [RehostedImage], isUnreadable: Bool) { ([image], false) }
    func add(_ image: RehostedImage) async throws {}
    func remove(id: String) async throws {}
}

private struct UnusedPreparer: ImagePreparing {
    func prepare(_ source: Data, maxDimension: Int) throws(ImagePreparationError) -> Data { source }
}

/// The image chips of the docked card (#653, operator reference of 2026-11-10): one per image the panel inserted while its
/// snippet is in the text; the ✕ takes the snippet out as one step of the history.
@MainActor
struct ComposerImageChipsTests {
    private let snippet = "[url=https://img.example/a.jpg][img]https://img.example/a.md.jpg[/img][/url]"
    private var chip: ComposerImageChip { ComposerImageChip(snippet: snippet, thumbnail: url("https://img.example/a.th.jpg")) }

    @Test func aChipShowsOnlyWhileItsSnippetIsInTheText() {
        let chip = chip
        #expect(ComposerImageChip.shown([chip], in: "Voilà \(snippet) !") == [chip])
        #expect(ComposerImageChip.shown([chip], in: "Voilà !").isEmpty, "typed away, cleared or undone")
    }

    @Test func itsCrossRemovesTheLastCopyOfItsSnippetOnly() {
        #expect(chip.removed(from: "a \(snippet) b \(snippet) c") == "a \(snippet) b  c")
        #expect(chip.removed(from: "nothing") == nil)
    }

    @Test func removingItIsOneStepUndoPutsTheImageBack() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        let text = "Regardez : \(snippet)"
        composer.update(text: text)
        composer.imageChips = [chip]
        #expect(composer.shownImageChips.count == 1)
        #expect(composer.removeImage(composer.imageChips[0]))
        #expect(composer.text == "Regardez : ")
        #expect(composer.shownImageChips.isEmpty)
        #expect(!composer.removeImage(composer.imageChips[0]), "already gone: nothing changes")
        composer.undo()
        #expect(composer.text == text)
        #expect(composer.shownImageChips.count == 1)
    }

    @Test func noChipIsRemovedWhileTheEditorIsLocked() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: snippet)
        composer.imageChips = [chip]
        // Archived drafts being moved lock the editor (`canEdit`), as a send does.
        composer.isMovingDrafts = true
        #expect(!composer.removeImage(composer.imageChips[0]))
        #expect(composer.text == snippet)
    }

    /// The chip finds the panel's upload behind a snippet it wrote, whatever the rendition; a link typed by hand has none, so
    /// nothing is loaded for it.
    @Test func theUploadBehindAnInsertedSnippetIsFoundAndAManualLinkHasNone() async throws {
        let image = RehostedImage(
            fullURL: url("https://img.example/a.jpg"), mediumURL: url("https://img.example/a.md.jpg"),
            miniURL: url("https://img.example/a.th.jpg"), width: 1200, height: 800, uploadedAt: Date(timeIntervalSince1970: 0)
        )
        let services = ImageUploadServices(
            uploader: nil, hostName: "img.example", preparer: UnusedPreparer(), history: OneImageHistory(image: image),
            settings: InMemorySettingsStore([:])
        )
        let panel = ImageUploadModel(services: services)
        await panel.load()
        for variant in image.availableVariants {
            #expect(panel.uploadedImage(writing: panel.snippet(for: image, variant: variant)) == image)
        }
        let manual = try #require(panel.manualSnippet(for: "https://example.com/b.jpg"))
        #expect(panel.uploadedImage(writing: manual) == nil)
    }
}
