import Foundation
import HFRModels
import Testing
@testable import HFRParsing

@Suite("Hop form parser")
struct HopFormParserTests {
    // MARK: - Captured forms

    @Test("R40a: reply composer, logged in")
    func replyLoggedIn() throws {
        let form = try HopFormParser.parse(Fixture.capture("R40a-reply-form-logged-in"))
        #expect(form.action == "/bddpost.php?config=hfr.inc")
        #expect(form.field(named: "hash_check")?.kind == .hidden)
        #expect(form.field(named: "hash_check")?.value == "REDACTED")
        #expect(form.field(named: "verifrequet")?.value == "1100")
        #expect(form.field(named: "pseudo")?.value == "user2")
        #expect(form.field(named: "pseudo")?.kind == .text)
        #expect(form.field(named: "password")?.kind == .password)
        #expect(form.field(named: "submit")?.kind == .submit)
        #expect(form.fields.count == 43)
        #expect(form.selects.isEmpty)
        // 16 tone radios, the first one checked; three unchecked options boxes keep their value.
        let tones = form.fields.filter { $0.name == "MsgIcon" }
        #expect(tones.count == 16)
        #expect(tones.filter(\.isChecked).map(\.value) == ["1"])
        let signature = try #require(form.field(named: "signature"))
        #expect(signature.kind == .checkbox)
        #expect(signature.value == "1")
        #expect(!signature.isChecked)
        #expect(form.textareaContent == nil)
        #expect(!form.isSubjectEditable)
        #expect(!form.isSubcategoryEditable)
        #expect(form.dynamicSmileys.isEmpty)
    }

    @Test("R40b: the anonymous composer has the form, an empty token and an empty pseudo; login is not inferred")
    func replyAnonymous() throws {
        let form = try HopFormParser.parse(Fixture.capture("R40b-reply-form-anon"))
        #expect(form.field(named: "hash_check")?.value == "")
        #expect(form.field(named: "pseudo")?.value == "")
        #expect(form.action == "/bddpost.php?config=hfr.inc")
    }

    @Test("R41a: quote prefill holds the quotemsg block, entities decoded, line breaks as LF")
    func quotePrefill() throws {
        let text = try #require(HopFormParser.parse(Fixture.capture("R41a-quote-form")).textareaContent)
        #expect(text.hasPrefix("[quotemsg=2666649,1,910001][#0055aa] [u][b]La pizza Napolitaine[/u][/b][/#0055aa] \n\n\n[url]"))
        #expect(text.hasSuffix("[/quotemsg]\n"))
        #expect(!text.contains("\r"))
        // The page writes the query separator of the cited links as `&amp;`; the prefill holds the decoded `&`.
        #expect(!text.contains("&amp;"))
        #expect(text.contains("viewtopic.php?f=135&t=34]"))
    }

    @Test("R41b: a quote of a quoting post, second value 3, CRLF read as LF")
    func quoteOfQuote() throws {
        let form = try HopFormParser.parse(Fixture.capture("R41b-quote-form-of-quoting-post"))
        #expect(form.textareaContent == "[quotemsg=2666695,3,910001]\n\ns'pas une pizza alors [:user5][/quotemsg]\n")
    }

    @Test(
        "R42 and R47c: a multiquote cookie prefills one quotemsg block per cited message",
        arguments: ["R42-multiquote-form-cookie", "R47c-mp-composer-multiquote-cookie"]
    )
    func multiquote(name: String) throws {
        let text = try #require(HopFormParser.parse(Fixture.capture(name)).textareaContent)
        #expect(text.matches(of: /\[quotemsg=[0-9]+,[0-9]+,[0-9]+\]/).count == 2)
        #expect(text.matches(of: /\[\/quotemsg\]/).count == 2)
    }

    @Test("R43a: the edit form posts to /bdd.php, offers the whole-topic delete box and a visible subject")
    func editFirstPost() throws {
        let form = try HopFormParser.parse(Fixture.capture("R43a-mp-edit-form-first-post"))
        #expect(form.action == "/bdd.php?config=hfr.inc")
        #expect(form.textareaContent == "fixture-test 1, line 1 (CRLF)\nline 2")
        let delete = try #require(form.field(named: "delete"))
        #expect(delete.kind == .checkbox)
        #expect(!delete.isChecked)
        #expect(form.isSubjectEditable)
        #expect(form.field(named: "sujet")?.value == "fixture-test-1")
    }

    @Test("R43b and R44: an edit of a later post has a hidden subject; R44 is served for another account's message")
    func editOtherPosts() throws {
        let later = try HopFormParser.parse(Fixture.capture("R43b-mp-edit-form-lf-post"))
        #expect(later.action == "/bdd.php?config=hfr.inc")
        #expect(later.textareaContent == "fixture-test 2, line 1 (LF) :)\nline 2")
        #expect(!later.isSubjectEditable)
        let other = try HopFormParser.parse(Fixture.capture("R44-mp-edit-form-other-account-message"))
        #expect(other.action == "/bdd.php?config=hfr.inc")
        #expect(other.textareaContent == "fixture-test 6, reply from user1")
        #expect(other.field(named: "delete") == nil)
    }

    @Test("R43c: the stored text stops before the emoji HFR refused")
    func editNonBMP() throws {
        let form = try HopFormParser.parse(Fixture.capture("R43c-mp-edit-form-nonbmp-post"))
        #expect(form.textareaContent == "fixture-test 3, before")
    }

    @Test("R45a: the new-topic form has a visible subject, toread fields and the sub-category select")
    func newTopic() throws {
        let form = try HopFormParser.parse(Fixture.capture("R45a-new-topic-form"))
        #expect(form.isSubjectEditable)
        #expect(form.isSubcategoryEditable)
        #expect((1...5).allSatisfy { form.field(named: "toread\($0)") != nil })
        let options = form.subcategories
        #expect(options.count == 16)
        #expect(options[0] == FormOption(value: "", label: "Aucune"))
        #expect(options[6] == FormOption(value: "426", label: "Arts & Lecture"))
        // Nothing is marked selected: a browser sends the first option, which is "no sub-category".
        let select = try #require(form.select(named: "subcat"))
        #expect(select.selectedValue == nil)
        #expect(select.effectiveValue == "")
        #expect(form.textareaContent == nil)
    }

    @Test("R45b: the new-MP form has the recipient prefilled and an editable subject")
    func newMP() throws {
        let form = try HopFormParser.parse(Fixture.capture("R45b-new-mp-form"))
        #expect(form.recipient == "user1")
        #expect(form.isSubjectEditable)
        #expect(!form.isSubcategoryEditable)
    }

    @Test("R47a: the MP quote form is a quotemsg block with ref 2")
    func mpQuote() throws {
        let form = try HopFormParser.parse(Fixture.capture("R47a-mp-quote-form"))
        #expect(form.textareaContent == "[quotemsg=1980875030,2,900002]fixture-test 2, edited (W15)[/quotemsg]\n")
    }

    @Test("R47b and R47u1: the MP reply composer has neither recipient nor sub-category; R47u1 lists favourite smileys")
    func mpReply() throws {
        let owner = try HopFormParser.parse(Fixture.capture("R47b-mp-reply-composer"))
        #expect(owner.recipient == nil)
        #expect(owner.field(named: "newdest") == nil)
        #expect(!owner.isSubjectEditable)
        #expect(owner.dynamicSmileys.isEmpty)
        let recipient = try HopFormParser.parse(Fixture.capture("R47u1-mp-reply-composer-recipient"))
        #expect(recipient.field(named: "pseudo")?.value == "user1")
        #expect(recipient.dynamicSmileys.count == 8)
        #expect(recipient.dynamicSmileys[0].code == "[:user3]")
        #expect(recipient.dynamicSmileys[0].url.absoluteString == "https://forum-images.hardware.fr/images/perso/user3.gif")
        #expect(recipient.dynamicSmileys.contains { $0.url.absoluteString.hasSuffix("/images/perso/1/user1.gif") })
    }

    @Test("R46: the moderation form is not a hop form; its action stays relative to /user/")
    func moderationForm() throws {
        let html = try Fixture.capture("R46-modo-alert-form")
        let form = try HopFormParser.parseModerationForm(html)
        #expect(form.action == "/user/modo.php?cat=13&ref=1&post=28563&numreponse=2666649&page=1&config=hfr.inc")
        #expect(form.fields.map(\.name) == ["hash_check", "referer_page", "Submit"])
        #expect(form.field(named: "Submit")?.kind == .submit)
        #expect(form.textareaContent == nil)
        #expect(throws: ParsingError.missingElement("form name=hop")) { try HopFormParser.parse(html) }
    }

    @Test("a hop form is not a moderation form")
    func moderationOnComposer() throws {
        #expect(throws: ParsingError.missingElement("form action*=modo.php")) {
            try HopFormParser.parseModerationForm(Fixture.capture("R40a-reply-form-logged-in"))
        }
    }

    @Test("pages without the form: a topic list, an empty body", arguments: ["R04-list-cat13-p1-anon", ""])
    func noForm(name: String) throws {
        let html = name.isEmpty ? name : try Fixture.capture(name)
        #expect(throws: ParsingError.missingElement("form name=hop")) { try HopFormParser.parse(html) }
    }
}
