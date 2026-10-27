import Foundation
import HFRModels
import Testing
@testable import HFRParsing

@Suite("Hop form layout")
struct HopFormLayoutTests {
    private static let composers = [
        "R40a-reply-form-logged-in", "R40b-reply-form-anon", "R41a-quote-form", "R41b-quote-form-of-quoting-post",
        "R42-multiquote-form-cookie", "R43a-mp-edit-form-first-post", "R43b-mp-edit-form-lf-post", "R43c-mp-edit-form-nonbmp-post",
        "R44-mp-edit-form-other-account-message", "R45a-new-topic-form", "R45b-new-mp-form", "R47a-mp-quote-form",
        "R47b-mp-reply-composer", "R47c-mp-composer-multiquote-cookie", "R47u1-mp-reply-composer-recipient"
    ]

    private func names(_ layout: HopFormLayout) -> [String] {
        layout.controls.map { control in
            switch control {
            case let .input(_, name, _), let .select(_, name, _), let .textarea(name, _), let .button(name): name
            }
        }
    }

    @Test("Indices line up with the parsed form on every captured composer", arguments: composers)
    func matchesParsedForm(file: String) throws {
        let html = try Fixture.capture(file)
        let form = try HopFormParser.parse(html)
        let layout = try HopFormParser.layout(html)
        var inputs: [String] = []
        var selects: [String] = []
        for control in layout.controls {
            switch control {
            case let .input(index, name, isDisabled):
                #expect(index == inputs.count && !isDisabled)
                inputs.append(name)
            case let .select(index, name, _):
                #expect(index == selects.count)
                selects.append(name)
            case let .textarea(name, isDisabled):
                #expect(name == "content_form" && !isDisabled)
            case .button:
                Issue.record("no captured composer has a named button")
            }
        }
        #expect(inputs == form.fields.map(\.name))
        #expect(selects == form.selects.map(\.name))
    }

    @Test("R40a: content_form sits between ColorUsedMem and wysiwyg, as in every captured POST")
    func textareaPosition() throws {
        let order = names(try HopFormParser.layout(Fixture.capture("R40a-reply-form-logged-in")))
        let index = try #require(order.firstIndex(of: "content_form"))
        #expect(order[index - 1] == "ColorUsedMem")
        #expect(order[index + 1] == "wysiwyg")
    }

    @Test("R45a: the subcat select follows toread5 and precedes the tone radios")
    func selectPosition() throws {
        let order = names(try HopFormParser.layout(Fixture.capture("R45a-new-topic-form")))
        let index = try #require(order.firstIndex(of: "subcat"))
        #expect(order[index - 1] == "toread5")
        #expect(order[index + 1] == "MsgIcon")
    }

    @Test("R43a and R43b: the delete box labels tell the first post from a later one")
    func deleteLabels() throws {
        let first = try HopFormParser.layout(Fixture.capture("R43a-mp-edit-form-first-post"))
        let later = try HopFormParser.layout(Fixture.capture("R43b-mp-edit-form-lf-post"))
        #expect(first.checkboxLabels["delete"] == "Effacer l'intégralité du sujet")
        #expect(later.checkboxLabels["delete"] == "Effacer ce message")
        #expect(later.checkboxLabels["smiley"] == "Désactiver les smilies")
    }

    @Test("Disabled controls, named buttons and unnamed controls on a small page")
    func inlineShapes() throws {
        let html = """
        <form name="hop" action="/bddpost.php"><input name="a" disabled><input type="button" value="x">
        <select name="s" disabled><option>1</option></select><textarea name="t" disabled></textarea>
        <button name="b">B</button><input name=""></form>
        """
        let layout = try HopFormParser.layout(html)
        #expect(layout.controls == [
            .input(index: 0, name: "a", isDisabled: true), .select(index: 0, name: "s", isDisabled: true),
            .textarea(name: "t", isDisabled: true), .button(name: "b"), .input(index: 1, name: "", isDisabled: false)
        ])
        #expect(try HopFormParser.parse(html).fields.map(\.name) == ["a", ""])
    }

    @Test("A page without a hop form throws")
    func missingForm() {
        #expect(throws: ParsingError.missingElement("form name=hop")) {
            try HopFormParser.layout("<a name=\"hop\"></a><div class=\"hop\">x</div>")
        }
    }
}
