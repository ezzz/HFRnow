import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004) of `HopFormParser` against the LOT-004 legacy `form` oracles, on the same captures.
/// Deviations from legacy are asserted as such and listed in `docs/lots/LOT-036-hop-form-parser.md`.
@Suite("Hop form parser against the legacy oracle")
struct HopFormOracleTests {
    static let composerCases = [
        "R40a", "R40b", "R41a", "R41b", "R42", "R43a", "R43b", "R43c", "R44", "R45a", "R45b", "R47a", "R47b", "R47c", "R47u1",
        "R60b", "R61b", "R62a", "R62b", "R63b"
    ]

    @Test("the case lists cover every LOT-004 form case")
    func casesCoverTheMap() throws {
        #expect(try Lot004FormOracle.mappedFormCases() == Set(Self.composerCases + ["R46"]))
    }

    @Test("action equals the legacy form action", arguments: composerCases)
    func action(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        #expect(form.action == oracle.legacy["formAction"] as? String)
    }

    @Test("what legacy would send (its rules applied to the parsed fields) equals the legacy inputData", arguments: composerCases)
    func inputData(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        let expected = try #require(oracle.legacy["inputData"] as? [String: String])
        #expect(Self.legacyInputData(of: form) == expected)
    }

    @Test("the inputs then the selects are the ones legacy walked, in the same order", arguments: composerCases)
    func order(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        let loop = try #require(oracle.legacy["loopOrder"] as? [String])
        // The oracle lists a select as `select:<name>`. Legacy skipped an input with no `value` attribute: the captures have none.
        #expect(form.fields.map(\.name) + form.selects.map { "select:" + $0.name } == loop)
    }

    @Test("textareaContent equals the legacy prefill (CRLF read as LF); nil where legacy had none", arguments: composerCases)
    func prefill(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        #expect(form.textareaContent == oracle.legacy["contentForm"] as? String)
        let raw = oracle.legacy["contentFormRaw"] as? String
        #expect(form.textareaContent == raw?.replacing("\r\n", with: "\n"))
    }

    @Test("derived flags and the subcat options equal the legacy ones", arguments: composerCases)
    func derived(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        #expect(form.isSubjectEditable == oracle.legacy["haveTitle"] as? Bool)
        #expect(form.isSubcategoryEditable == oracle.legacy["haveCategory"] as? Bool)
        #expect((form.recipient != nil) == oracle.legacy["haveTo"] as? Bool)
        let subcats = try #require(oracle.legacy["subcats"] as? [[String: String]])
        #expect(form.subcategories.map { ["id": $0.value, "title": $0.label] } == subcats)
    }

    @Test("favourite smileys equal the legacy list", arguments: composerCases)
    func smileys(id: String) throws {
        let oracle = try Lot004FormOracle.load(id)
        let form = try HopFormParser.parse(oracle.html)
        let legacy = try #require(oracle.legacy["smileys"] as? [[String: String]])
        #expect(form.dynamicSmileys.map { ["alt": $0.code, "src": $0.url.absoluteString] } == legacy)
    }

    @Test("R46: the moderation form equals the legacy inputs and action, with no prefill")
    func moderation() throws {
        let oracle = try Lot004FormOracle.load("R46")
        let form = try HopFormParser.parseModerationForm(oracle.html)
        // Legacy kept the relative action and prefixed `/user/` when building the URL (`AlerteModoViewController.m:176`).
        #expect(form.action == "/user/" + (oracle.legacy["formAction"] as? String ?? "?"))
        let expected = try #require(oracle.legacy["inputData"] as? [String: String])
        #expect(Self.legacyInputData(of: form) == expected)
        #expect(form.textareaContent == nil)
        #expect(form.selects.isEmpty)
    }

    // MARK: - Legacy rules

    /// `QuoteMessageViewController.m:209-290` on parsed fields: `MsgIcon` only when checked, checkbox `"1"`/`"0"`, others
    /// their value, selects their selected or first option; a later field of the same name replaces an earlier one.
    static func legacyInputData(of form: ForumForm) -> [String: String] {
        var data: [String: String] = [:]
        for field in form.fields {
            if field.name == "MsgIcon" {
                if field.isChecked { data[field.name] = field.value }
            } else if field.kind == .checkbox {
                data[field.name] = field.isChecked ? "1" : "0"
            } else {
                data[field.name] = field.value
            }
        }
        for select in form.selects {
            data[select.name] = select.effectiveValue
        }
        return data
    }
}
