import Foundation
import Testing
@testable import HFRClient

/// The selection formatter: legacy's cases (`HFRswiftTests/ReplyPostingServiceTests.swift:1101-1132` at `2440d79`), then
/// what legacy left unsaid, on small prefills and on the captured multi-quote prefill of `R47c`.
@Suite("Quote selection formatter")
struct QuoteSelectionFormatterTests {
    private static let single = "[quotemsg=1,2,3]Bonjour tout le monde[/quotemsg]\n"
    /// `R47c`'s prefill as HFR serves it, line breaks read as `\n` (LOT-036): two blocks, each followed by two LF.
    private static let captured = "[quotemsg=1980875029,1,900002]fixture-test 1, line 1 (CRLF)\nline 2[/quotemsg]\n\n"
        + "[quotemsg=1980875030,2,900002]fixture-test 2, edited (W15)[/quotemsg]\n\n"

    private func format(_ prefill: String, _ selection: String, bold: Bool) -> String {
        QuoteSelectionFormatter.format(prefill, selection: selection, bold: bold)
    }

    // MARK: - Legacy cases

    @Test("One block: the selection replaces its text")
    func keepsOnlySelection() {
        #expect(format(Self.single, "tout le monde", bold: false) == "[quotemsg=1,2,3]tout le monde[/quotemsg]\n")
    }

    @Test("One block: the selection is bolded in the whole quote")
    func boldsSelection() {
        #expect(format(Self.single, "tout le monde", bold: true) == "[quotemsg=1,2,3]Bonjour [b]tout le monde[/b][/quotemsg]\n")
    }

    @Test("Several blocks: the block holding the selection is kept alone")
    func usesMatchingBlock() {
        let prefill = "[quotemsg=1,2,3]Premier message[/quotemsg]\n[quotemsg=4,5,6]Deuxieme message cible[/quotemsg]"
        #expect(format(prefill, "message cible", bold: false) == "[quotemsg=4,5,6]message cible[/quotemsg]\n")
    }

    // MARK: - Beyond legacy's tests

    @Test("The multi-quote prefill used here is R47c's, as the flow returns it")
    func capturedPrefill() throws {
        #expect(Self.captured == (try QuoteCapture.prefill("R47c").decoded))
    }

    @Test("An empty selection, once trimmed, changes nothing", arguments: ["", "  ", " \n\t "])
    func emptySelection(selection: String) {
        #expect(format(Self.single, selection, bold: false) == Self.single)
        #expect(format(Self.captured, selection, bold: true) == Self.captured)
    }

    @Test("The selection is trimmed of whitespace and newlines")
    func trimsSelection() {
        #expect(format(Self.single, " \ntout le monde \n", bold: false) == "[quotemsg=1,2,3]tout le monde[/quotemsg]\n")
    }

    @Test("Matching ignores case; the bolded text keeps the case it has in the message")
    func caseInsensitive() {
        #expect(format(Self.single, "TOUT LE MONDE", bold: true) == "[quotemsg=1,2,3]Bonjour [b]tout le monde[/b][/quotemsg]\n")
        #expect(format(Self.captured, "EDITED", bold: false) == "[quotemsg=1980875030,2,900002]EDITED[/quotemsg]\n")
    }

    @Test("Only the first occurrence is bolded (legacy ObjC replaced every case-sensitive one)")
    func firstOccurrenceOnly() {
        #expect(
            format("[quotemsg=1,2,3]Bonjour, bonjour[/quotemsg]\n", "bonjour", bold: true)
                == "[quotemsg=1,2,3][b]Bonjour[/b], bonjour[/quotemsg]\n"
        )
        #expect(
            format("[quotemsg=1,2,3]bonjour, bonjour[/quotemsg]\n", "bonjour", bold: true)
                == "[quotemsg=1,2,3][b]bonjour[/b], bonjour[/quotemsg]\n"
        )
    }

    @Test("Selection not found: one block is narrowed anyway, bolding changes nothing, several blocks change nothing")
    func selectionNotFound() {
        #expect(format(Self.single, "ailleurs", bold: false) == "[quotemsg=1,2,3]ailleurs[/quotemsg]\n")
        #expect(format(Self.single, "ailleurs", bold: true) == Self.single)
        #expect(format(Self.captured, "ailleurs", bold: false) == Self.captured)
        #expect(format(Self.captured, "ailleurs", bold: true) == Self.captured)
    }

    @Test("A selection over two blocks matches neither: the prefill is unchanged")
    func selectionOverTwoBlocks() {
        #expect(format(Self.captured, "line 2\n\nfixture-test 2", bold: false) == Self.captured)
        #expect(format(Self.captured, "line 2 fixture-test 2", bold: true) == Self.captured)
    }

    @Test("Captured multi-quote: a selection over two lines of the first block")
    func capturedFirstBlock() {
        #expect(
            format(Self.captured, "(CRLF)\nline 2", bold: true)
                == "[quotemsg=1980875029,1,900002]fixture-test 1, line 1 [b](CRLF)\nline 2[/b][/quotemsg]\n"
        )
        #expect(format(Self.captured, "line 1 (CRLF)", bold: false) == "[quotemsg=1980875029,1,900002]line 1 (CRLF)[/quotemsg]\n")
    }

    @Test("The selection is looked for in the quoted text, never in a tag")
    func tagsAreNotSearched() {
        #expect(format(Self.single, "2", bold: true) == Self.single)
        #expect(format(Self.single, "quotemsg", bold: true) == Self.single)
        // Both tags hold the author's number, no quoted text does (legacy matched the first block by its tag).
        #expect(format(Self.captured, "900002", bold: true) == Self.captured)
        #expect(format(Self.captured, "900002", bold: false) == Self.captured)
    }

    @Test("Tags are kept as served, never rebuilt")
    func tagsKeptAsServed() {
        let upper = "[QUOTEMSG=1,2,3]Bonjour tout le monde[/QUOTEMSG]\n"
        #expect(format(upper, "tout", bold: false) == "[QUOTEMSG=1,2,3]tout[/QUOTEMSG]\n")
        let large = "[quotemsg=9223372036854775807,40,4294967297]Bonjour[/quotemsg]\n"
        #expect(format(large, "Bonjour", bold: false) == large)
    }

    @Test("Bolding one block keeps what surrounds it and ends the prefill with a line break")
    func boldKeepsSurroundings() {
        #expect(format("[quotemsg=1,2,3]Bonjour[/quotemsg]", "jour", bold: true) == "[quotemsg=1,2,3]Bon[b]jour[/b][/quotemsg]\n")
        #expect(format("\n[quotemsg=1,2,3]Bonjour[/quotemsg]\n\n", "jour", bold: true) == "\n[quotemsg=1,2,3]Bon[b]jour[/b][/quotemsg]\n\n")
    }

    @Test("A prefill without a well-formed block is returned unchanged", arguments: [
        "Bonjour tout le monde", "[quotemsg=1,2]Bonjour[/quotemsg]", "[quotemsg=1,2,3]Bonjour", "[quote]Bonjour[/quote]"
    ])
    func noBlock(prefill: String) {
        #expect(format(prefill, "Bonjour", bold: false) == prefill)
        #expect(format(prefill, "Bonjour", bold: true) == prefill)
    }
}
