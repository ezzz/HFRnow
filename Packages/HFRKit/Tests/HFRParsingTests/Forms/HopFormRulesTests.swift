import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Rules of `HopFormParser` on small inline pages (the captured forms are in `HopFormParserTests`).
@Suite("Hop form parser rules")
struct HopFormRulesTests {
    @Test("values, labels and actions are entity-decoded; checked is a presence test; unnamed controls are skipped")
    func fieldRules() throws {
        let form = try HopFormParser.parse("""
            <form name="hop" action="/bddpost.php?config=hfr.inc&amp;x=1">
            <input type="hidden" name="sujet" value="Topic &amp; &quot;fun&quot; l&#039;ami" />
            <input type="checkbox" name="bare" checked />
            <input type="CHECKBOX" name="full" value="1" checked="checked" />
            <input type="checkbox" name="unchecked" value="1" />
            <input type="image" name="geo" /><input name="plain" /><input value="orphan" /><input type="file" name="up" />
            </form>
            """)
        #expect(form.action == "/bddpost.php?config=hfr.inc&x=1")
        #expect(form.field(named: "sujet")?.value == "Topic & \"fun\" l'ami")
        #expect(form.field(named: "bare") == FormField(name: "bare", value: "", kind: .checkbox, isChecked: true))
        #expect(form.field(named: "full")?.isChecked == true)
        #expect(form.field(named: "unchecked")?.isChecked == false)
        #expect(form.field(named: "geo")?.kind == .other)
        #expect(form.field(named: "plain") == FormField(name: "plain"))
        #expect(form.fields.map(\.name) == ["sujet", "bare", "full", "unchecked", "geo", "plain", "up"])
    }

    @Test("selects: selected option, none selected, option without value, option groups, unnamed select")
    func selectRules() throws {
        let form = try HopFormParser.parse("""
            <form name="hop"><select name="a"><option value="1">One</option>
            <option value="2" selected="selected">T&eacute;</option></select>
            <select name="b"><option value="x"> Ex </option><option>Bare &amp; text</option></select>
            <select name="c"><optgroup label="g"><option value="g1">G1</option></optgroup><option value="g2" selected>G2</option></select>
            <select name="d"></select>
            <select name="e"><option value="1" selected>1</option><option value="2" selected>2</option></select>
            <select><option value="z">Z</option></select></form>
            """)
        #expect(form.selects.map(\.name) == ["a", "b", "c", "d", "e"])
        #expect(form.select(named: "a")?.selectedValue == "2")
        #expect(form.select(named: "a")?.options[1].label == "Té")
        #expect(form.select(named: "b")?.selectedValue == nil)
        #expect(form.select(named: "b")?.effectiveValue == "x")
        #expect(form.select(named: "b")?.options == [
            FormOption(value: "x", label: "Ex"), FormOption(value: "Bare & text", label: "Bare & text")
        ])
        #expect(form.select(named: "c")?.options.map(\.value) == ["g1", "g2"])
        #expect(form.select(named: "c")?.effectiveValue == "g2")
        #expect(form.select(named: "d")?.effectiveValue == nil)
        // Legacy took the first selected option (a browser would take the last); unverified on HFR pages, none has two.
        #expect(form.select(named: "e")?.selectedValue == "1")
    }

    @Test("the textarea: entities decoded, CRLF and CR become LF, empty is nil, only #content_form counts")
    func textareaRules() throws {
        func prefill(_ body: String) throws -> String? {
            try HopFormParser.parse("<form name=\"hop\">\(body)</form>").textareaContent
        }
        let encoded = "<textarea id=\"content_form\">a &lt;b&gt; &amp;amp; \"q\"\r\nline\rend</textarea>"
        #expect(try prefill(encoded) == "a <b> &amp; \"q\"\nline\nend")
        #expect(try prefill("<textarea id=\"content_form\"></textarea>") == nil)
        #expect(try prefill("<textarea name=\"raison\">not it</textarea>") == nil)
        #expect(try prefill("<div id=\"content_form\">not a textarea</div>") == nil)
        #expect(try prefill("<textarea id=\"content_form\">  keep   spaces\n\n</textarea>") == "  keep   spaces\n\n")
        // A browser drops one newline right after the tag; legacy and this parser keep it (no capture has one).
        #expect(try prefill("<textarea id=\"content_form\">\nx</textarea>") == "\nx")
    }

    @Test("only the hop form's own controls are read; an element named hop that is not a form is not the form")
    func scope() throws {
        let form = try HopFormParser.parse("""
            <form id="fastsearch"><input type="hidden" name="hash_check" value="outside" /></form>
            <a name="hop"></a>
            <form name="hop" action="/a"><input name="inside" value="1" /><textarea id="content_form">in</textarea></form>
            <form name="other"><input name="after" /></form><textarea id="content_form">elsewhere</textarea>
            """)
        #expect(form.fields.map(\.name) == ["inside"])
        #expect(form.textareaContent == "in")
        let anchorOnly = "<a name=\"hop\"></a><input name=\"x\" />"
        #expect(throws: ParsingError.missingElement("form name=hop")) { try HopFormParser.parse(anchorOnly) }
    }

    @Test("the action stays on the forum origin: other hosts, protocol-relative, http, other ports are refused",
          arguments: [
              "https://evil.example/x", "//evil.example/x", "http://evil.example/x",
              "http://forum.hardware.fr:80/bddpost.php", "https://forum.hardware.fr:8443/bddpost.php",
              "https://forum.hardware.fr//evil.example/x", "https://user@forum.hardware.fr/x", "javascript:alert(1)", ""
          ])
    func offOriginAction(action: String) throws {
        let form = try HopFormParser.parse("<form name=\"hop\" action=\"\(action)\"><input name=\"a\" /></form>")
        #expect(form.action == nil)
        #expect(form.fields.map(\.name) == ["a"])
    }

    @Test("a backslash after the slash cannot turn the path into another host")
    func backslashAction() throws {
        let form = try HopFormParser.parse("<form name=\"hop\" action=\"/\\evil.example/x\"></form>")
        // Foundation reads the backslash as path text, so the result stays a forum path with the character escaped.
        #expect(form.action == nil || form.action?.hasPrefix("/%5C") == true)
    }

    @Test("forum actions are kept as paths: absolute URL, https on 443, absolute path, relative to the page")
    func forumActions() throws {
        func action(_ value: String, page: URL = HFRURL.base) throws -> String? {
            try HopFormParser.parse("<form name=\"hop\" action=\"\(value)\"></form>", pageURL: page).action
        }
        #expect(try action("https://forum.hardware.fr/bddpost.php?config=hfr.inc") == "/bddpost.php?config=hfr.inc")
        #expect(try action("https://forum.hardware.fr:443/bdd.php?a=1&amp;b=2") == "/bdd.php?a=1&b=2")
        #expect(try action("http://forum.hardware.fr/bdd.php") == "/bdd.php")
        #expect(try action("/bddpost.php?config=hfr.inc") == "/bddpost.php?config=hfr.inc")
        let page = try #require(URL(string: "https://forum.hardware.fr/user/modo.php?cat=13"))
        #expect(try action("bddpost.php?x=1", page: page) == "/user/bddpost.php?x=1")
    }

    @Test("the moderation action is resolved against /user/ and refused off-origin")
    func moderationAction() throws {
        func action(_ value: String) throws -> String? {
            try HopFormParser.parseModerationForm("<form action=\"\(value)\">modo.php</form>").action
        }
        #expect(try action("modo.php?cat=13&amp;ref=1") == "/user/modo.php?cat=13&ref=1")
        #expect(try action("https://evil.example/modo.php") == nil)
        #expect(try action("//evil.example/modo.php") == nil)
    }

    @Test("a form without action keeps nil; favourite smileys keep alt and https image, skip the unusable ones")
    func smileyRules() throws {
        let form = try HopFormParser.parse("""
            <form name="hop"></form>
            <div id="dynamic_smilies"><img src="/images/perso/a.gif" alt="[:a]" /><img src="javascript:alert(1)" alt="[:evil]" />
            <img src="/images/perso/noalt.gif" /><img src="/images/perso/empty.gif" alt="" /><img alt="[:nosrc]" />
            <img src="http://forum-images.hardware.fr/images/perso/o'b r.gif" alt="[:o'b r]" /></div>
            """)
        #expect(form.action == nil)
        #expect(form.dynamicSmileys.map(\.code) == ["[:a]", "[:o'b r]"])
        #expect(form.dynamicSmileys[0].url.absoluteString == "https://forum.hardware.fr/images/perso/a.gif")
    }
}
