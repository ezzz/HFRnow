import Foundation
import Testing
@testable import HFRModels

@Suite struct RehostedImageTests {
    private let full = URL(string: "https://img3.super-h.fr/i/full.jpg") ?? URL(fileURLWithPath: "/")
    private let medium = URL(string: "https://img3.super-h.fr/i/medium.jpg") ?? URL(fileURLWithPath: "/")
    private let mini = URL(string: "https://img3.super-h.fr/i/mini.jpg") ?? URL(fileURLWithPath: "/")
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func image(medium: Bool = true, mini: Bool = true) -> RehostedImage {
        RehostedImage(
            fullURL: full,
            mediumURL: medium ? self.medium : nil,
            miniURL: mini ? self.mini : nil,
            width: 1200,
            height: 800,
            uploadedAt: date
        )
    }

    @Test func roundTrips() throws {
        #expect(try roundTrip(image()) == image())
    }

    @Test func snippetFormatsMatchTheLegacyBBCode() {
        let image = image()
        #expect(image.snippet(variant: .full, mode: .linkOnly) == full.absoluteString)
        #expect(image.snippet(variant: .medium, mode: .imageNoLink) == "[img]\(medium.absoluteString)[/img]\n")
        #expect(image.snippet(variant: .mini, mode: .imageWithLink)
            == "[url=\(full.absoluteString)][img]\(mini.absoluteString)[/img][/url]\n")
    }

    @Test func missingRenditionsFallBackToLargerOnes() {
        #expect(image(mini: false).url(for: .mini) == medium)
        #expect(image(medium: false, mini: false).url(for: .mini) == full)
        #expect(image(medium: false).url(for: .medium) == full)
    }

    @Test func availableVariantsListWhatExists() {
        #expect(image().availableVariants == [.full, .medium, .mini])
        #expect(image(medium: false).availableVariants == [.full, .mini])
        #expect(image(medium: false, mini: false).availableVariants == [.full])
    }

    @Test func identityDistinguishesTwoUploadsOfTheSameImage() {
        let later = RehostedImage(fullURL: full, uploadedAt: date.addingTimeInterval(5))
        #expect(image().id != later.id)
        #expect(image().id == image().id)
    }

    @Test func modeRawValuesMatchTheLegacySetting() {
        #expect(RehostBBCodeMode.imageWithLink.rawValue == 0)
        #expect(RehostBBCodeMode.imageNoLink.rawValue == 1)
        #expect(RehostBBCodeMode.linkOnly.rawValue == 2)
    }
}
