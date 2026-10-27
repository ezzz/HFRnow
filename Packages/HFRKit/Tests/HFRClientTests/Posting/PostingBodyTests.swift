import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// Browser rules of `PostingBody` on small models, and the differential against the LOT-004 legacy oracle.
/// A textarea placed after the input at `after` in a test layout.
private struct TestTextarea {
    var after: Int
    var name = "content_form"
    var disabled = false
}

@Suite("Posting body")
struct PostingBodyTests {
    private let base = [
        FormField(name: "hash_check", value: "t", kind: .hidden), FormField(name: "verifrequet", value: "1100", kind: .hidden)
    ]

    private func layout(_ form: ForumForm, textareas: [TestTextarea] = [], disabled: Set<Int> = [])
        -> HopFormLayout {
        var controls: [HopFormLayout.Control] = []
        for (index, field) in form.fields.enumerated() {
            controls.append(.input(index: index, name: field.name, isDisabled: disabled.contains(index)))
            for area in textareas where area.after == index {
                controls.append(.textarea(name: area.name, isDisabled: area.disabled))
            }
        }
        for (index, select) in form.selects.enumerated() {
            controls.append(.select(index: index, name: select.name, isDisabled: false))
        }
        return HopFormLayout(controls: controls)
    }

    private func names(_ body: FormBody) -> [String] { body.fields.map(\.name) }

    @Test("Disabled controls, unnamed inputs, unclicked submits and buttons are not sent; repeated names all are")
    func browserRules() throws {
        let form = ForumForm(
            action: "/bddpost.php?config=hfr.inc",
            fields: base + [
                FormField(name: "subcat", value: "0", kind: .hidden), FormField(name: "subcat", value: "0", kind: .hidden),
                FormField(name: "off", value: "x", kind: .hidden), FormField(name: "", value: "x", kind: .text),
                FormField(name: "submit", value: "Valider", kind: .submit), FormField(name: "submit2", value: "Autre", kind: .submit),
                FormField(name: "box", value: "1", kind: .checkbox, isChecked: true)
            ]
        )
        var shape = layout(form, textareas: [TestTextarea(after: 1)], disabled: [4])
        shape.controls.append(.button(name: "preview"))
        let body = try PostingBody.make(form: form, layout: shape, text: "a\nb")
        #expect(names(body) == ["hash_check", "verifrequet", "content_form", "subcat", "subcat", "submit", "box"])
        #expect(body.encodedString.contains("content_form=a%0D%0Ab"))
    }

    @Test("Checkbox overrides apply to checkboxes only; a radio keeps the page's choice")
    func checkboxOverrides() throws {
        let form = ForumForm(fields: base + [
            FormField(name: "MsgIcon", value: "1", kind: .radio, isChecked: true), FormField(name: "MsgIcon", value: "2", kind: .radio),
            FormField(name: "smiley", value: "1", kind: .checkbox),
            FormField(name: "signature", value: "1", kind: .checkbox, isChecked: true)
        ])
        let body = try PostingBody.make(
            form: form, layout: layout(form, textareas: [TestTextarea(after: 1)]), text: "t",
            checkboxes: ["smiley": true, "signature": false, "MsgIcon": true]
        )
        #expect(body.fields.filter { $0.name == "MsgIcon" }.map(\.value) == ["1"])
        #expect(names(body).contains("smiley"))
        #expect(!names(body).contains("signature"))
    }

    @Test("Overrides replace text and select values; a select without options is not sent")
    func overrides() throws {
        let form = ForumForm(
            fields: base + [FormField(name: "sujet", value: "old", kind: .text)],
            selects: [
                FormSelect(name: "subcat", options: [FormOption(value: "", label: "Aucune"), FormOption(value: "7", label: "x")]),
                FormSelect(name: "empty")
            ]
        )
        let body = try PostingBody.make(
            form: form, layout: layout(form, textareas: [TestTextarea(after: 2)]), text: "t", overrides: ["sujet": "new", "subcat": "7"]
        )
        let sent = body.fields.map { "\($0.name)=\($0.value)" }
        #expect(sent == ["hash_check=t", "verifrequet=1100", "sujet=new", "content_form=t", "subcat=7"])
    }

    @Test(
        "Forms the engine cannot send like a browser are refused",
        arguments: ["other input type", "other textarea", "no content", "disabled content", "no verifrequet", "layout"]
    )
    func unsupportedForms(variant: String) {
        var fields = base
        var textarea = TestTextarea(after: 0)
        switch variant {
        case "other input type": fields.append(FormField(name: "file", kind: .other))
        case "other textarea": textarea.name = "notes"
        case "disabled content": textarea.disabled = true
        case "no verifrequet": fields.removeLast()
        default: break
        }
        let form = ForumForm(fields: fields)
        var shape = layout(form, textareas: variant == "no content" ? [] : [textarea])
        if variant == "layout" { shape.controls.removeFirst() }
        do {
            _ = try PostingBody.make(form: form, layout: shape, text: "t")
            Issue.record("\(variant) was accepted")
        } catch {
            guard case .unsupportedForm = error else {
                Issue.record("\(variant): \(error)")
                return
            }
        }
    }
}

/// The parts of a LOT-004 `form` oracle the differential test reads.
private struct LegacyFormOracle: Decodable {
    let result: LegacyFormResult
}

private struct LegacyFormResult: Decodable {
    let legacy: LegacyFormPost
}

private struct LegacyFormPost: Decodable {
    let postedContent: String?
    let post: LegacyPairs?
}

private struct LegacyPairs: Decodable {
    let pairs: [[String]]
}

/// The posted fields match what legacy posted from the same captured form (LOT-004 `form` oracle, `legacy.post.pairs`),
/// except for the documented differences: an unchecked box is not sent (legacy `"0"`), and `hash_check` comes from the
/// form (legacy: the account's stored token, here the oracle's fake one).
@Suite("Posting body: legacy oracle")
struct PostingBodyOracleTests {
    private static func oracle(_ id: String) throws -> LegacyFormOracle {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-004/\(id).oracle.json")
        return try JSONDecoder().decode(LegacyFormOracle.self, from: try Data(contentsOf: url))
    }

    @Test(
        "Same fields and values as legacy on every captured composer",
        arguments: ["R40a", "R41a", "R41b", "R42", "R43a", "R43b", "R43c", "R44", "R45a", "R45b", "R47a", "R47b", "R47c", "R47u1"]
    )
    func legacyPairs(id: String) throws {
        let legacy = try Self.oracle(id).result.legacy
        let html = try Capture.page(try #require(PostingCapture.forms[id]))
        let form = try HopFormParser.parse(html, pageURL: try PostingCapture.pageURL(id))
        let layout = try HopFormParser.layout(html)
        let text = try #require(legacy.postedContent)
        let ours = try PostingBody.make(form: form, layout: layout, text: text).fields.map { [$0.name, $0.value] }
        let uncheckedBoxes = Set(form.fields.filter { $0.kind == .checkbox && !$0.isChecked }.map(\.name))
        let theirs = try #require(legacy.post?.pairs).filter { !(uncheckedBoxes.contains($0[0]) && $0[1] == "0") }
        func normalized(_ pairs: [[String]]) -> [String] {
            pairs.map { $0[0] == "hash_check" ? "hash_check=<token>" : "\($0[0])=\($0[1].replacing("\r\n", with: "\n"))" }.sorted()
        }
        #expect(normalized(ours) == normalized(theirs))
        #expect(!uncheckedBoxes.isEmpty)
    }
}
