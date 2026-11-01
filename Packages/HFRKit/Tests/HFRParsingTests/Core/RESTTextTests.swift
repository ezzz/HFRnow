import Foundation
import Testing
@testable import HFRParsing

/// The two readers of REST API text (LOT-057): `last_post_date` and entity-escaped names.
@Suite("REST dates and names (LOT-057)")
struct RESTTextTests {
    @Test(
        "last_post_date: Paris wall-clock time, both offsets and the DST changes",
        arguments: [
            ("2026-10-26 04:10", "2026-10-26T03:10:00Z"), // R57b, the day after fall-back: CET
            ("2026-10-24 12:44", "2026-10-24T10:44:00Z"), // R57b, CEST
            ("2003-01-15 14:53", "2003-01-15T13:53:00Z"), // R57b, topic 1
            ("2025-03-30 01:59", "2025-03-30T00:59:00Z"),
            ("2025-03-30 03:00", "2025-03-30T01:00:00Z"),
            ("2025-10-26 02:30", "2025-10-26T00:30:00Z") // repeated hour: its first occurrence (CEST)
        ]
    )
    func restDates(text: String, iso: String) {
        #expect(HFRDate.restDate(from: text) == HFRDateTests.utc(iso))
    }

    @Test(
        "Anything but exactly yyyy-MM-dd HH:mm, or a time that does not exist, is nil",
        arguments: [
            "2025-03-30 02:30", "2026-02-30 12:00", "2026-10-26 24:00", "2026-10-26 04:10:00", " 2026-10-26 04:10",
            "2026-10-26T04:10", "26-10-2026 à 04:10", "2026-1-26 04:10", "", "2026-10-26 04:1٠"
        ]
    )
    func invalidRestDates(text: String) {
        #expect(HFRDate.restDate(from: text) == nil)
    }

    @Test("Names lose their entities, plain text stays as is")
    func entities() {
        #expect(HFRText.decodingHTMLEntities("Overclocking, Cooling &amp; Modding") == "Overclocking, Cooling & Modding")
        #expect(HFRText.decodingHTMLEntities("Syst&egrave;mes &#38; R&#xE9;seaux") == "Systèmes & Réseaux")
        #expect(HFRText.decodingHTMLEntities(" Nos amis les animaux") == " Nos amis les animaux")
        #expect(HFRText.decodingHTMLEntities("") == "")
    }
}
