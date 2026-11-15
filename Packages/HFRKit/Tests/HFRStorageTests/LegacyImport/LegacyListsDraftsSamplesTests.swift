import Foundation
@testable import HFRStorage
import Testing

/// The #709 samples: pseudo lists and drafts written by the legacy app's own code (`21173e77`) on synthetic data
/// (MANIFEST "Legacy on-device samples", `tooling/legacy-oracle/stores-709-master.patch`), read by the LOT-067 decoders.
@Suite("Legacy lists and drafts samples (#709)")
struct LegacyListsDraftsSamplesTests {
    private func plist(_ name: String) throws -> LegacyValue {
        try #require(LegacyValue.parse(try LegacySamples.data(name)))
    }

    private func defaults(_ name: String) throws -> InMemoryLegacyDefaults {
        InMemoryLegacyDefaults(plist: try LegacySamples.data(name))
    }

    @Test("blackListDico.plist: one list per account, in the order the real adds wrote them")
    func blocklists() throws {
        #expect(LegacyFormats.blocklists(try plist("lists-typical-blackListDico.plist"))
            == ["fakeaccount1": ["fakeblocked1", "fake blocked 2", "fäkeblöcked3"]])
        #expect(LegacyFormats.blocklists(try plist("lists-two-accounts-blackListDico.plist")) == [
            "fakeaccount1": ["fakeblocked1", "fake blocked 2", "fäkeblöcked3"], "fakeaccount2": ["fakeblocked4"]
        ])
        #expect(LegacyFormats.blocklists(try plist("lists-emptied-blackListDico.plist")) == ["fakeaccount1": [], "fakeaccount2": []])
        #expect(LegacyFormats.blocklists(try plist("lists-v0-after-load-and-add-blackListDico.plist"))
            == ["fakeaccount1": ["fakeoldblocked1", "fake old blocked 2", "fakeblocked5"]])
    }

    @Test("whiteList.plist and the v0 blackList.plist are plain lists")
    func lists() throws {
        #expect(LegacyFormats.pseudoList(try plist("lists-typical-whiteList.plist")) == ["fakeallowed1", "fake allowed 2"])
        #expect(LegacyFormats.pseudoList(try plist("lists-emptied-whiteList.plist")) == [])
        #expect(LegacyFormats.pseudoList(try plist("lists-v0-input-blackList.plist")) == ["fakeoldblocked1", "fake old blocked 2"])
    }

    @Test("brouillon: the string the composer saved; erased is an empty string; absent is no value")
    func brouillon() throws {
        #expect(try defaults("defaults-brouillon-typical.plist").value(forKey: LegacyKeys.objcDraft)
            == .string("Un brouillon fictif\nsur deux lignes [b]gras[/b] é"))
        #expect(try defaults("defaults-brouillon-erased.plist").value(forKey: LegacyKeys.objcDraft) == .string(""))
        #expect(try defaults("defaults-brouillon-absent.plist").value(forKey: LegacyKeys.objcDraft) == nil)
    }

    @Test("active drafts: newest first, blank texts never stored, a removal empties the key, 50 topics kept")
    func activeDrafts() throws {
        let typical = try #require(LegacyFormats.activeDrafts(
            try defaults("defaults-active-drafts-typical.plist").value(forKey: LegacyKeys.activeReplyDrafts)))
        #expect(typical.map(\.topicNumber) == [9_800_101, 9_800_102])
        #expect(typical.map(\.text) == ["Réponse fictive modifiée", "  deuxième brouillon fictif  "])
        #expect(typical[0].updatedAt > typical[1].updatedAt)
        let oneRemoved = try #require(LegacyFormats.activeDrafts(
            try defaults("defaults-active-drafts-one-removed.plist").value(forKey: LegacyKeys.activeReplyDrafts)))
        #expect(oneRemoved.map(\.topicNumber) == [9_800_101])
        #expect(try defaults("defaults-active-drafts-emptied.plist").value(forKey: LegacyKeys.activeReplyDrafts) == nil)
        #expect(try defaults("defaults-active-drafts-absent.plist").value(forKey: LegacyKeys.activeReplyDrafts) == nil)
        let capped = try #require(LegacyFormats.activeDrafts(.data(try LegacySamples.data("active-drafts-51-topics.json"))))
        #expect(capped.count == 50)
        #expect(capped.first?.topicNumber == 9_800_251)
        #expect(!capped.contains { $0.topicNumber == 9_800_201 })
    }
}
