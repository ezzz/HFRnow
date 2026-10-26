import HFRModels
import Testing
@testable import HFRParsing

@Suite("Poll parser")
struct PollParserTests {
    private static let expectedLabels = [
        "SP 95-98 je veux même pas entendre parler du E10 ou plus !",
        "Je roule au SP95-E10, pas testé plus d'éthanol",
        "E85 entre 25 & 40 % + SP",
        "E85 à environ la moitié (45 à 55 %) + SP",
        "E85 entre 60 & 75 % + SP",
        "plus de 75 % mais je rajoute une lampée de SP",
        "seulement E85 sans modification du moteur",
        "seulement E85 avec boitier / modif' du moteur",
        "Dark Vador enfume tout le monde avec son mazout",
        "Obi-Wan Kenobi se déplace en land speeder électrique"
    ]

    private func votable(_ poll: Poll?) throws -> (options: [PollOption], hidden: [String: String]) {
        let poll = try #require(poll)
        guard case .votable(let options, let hidden) = poll.kind else {
            Issue.record("Expected a voting form")
            return ([], [:])
        }
        return (options, hidden)
    }

    @Test("R32a (logged out): question, ten radio answers, hidden fields with an empty token")
    func anonymousVoteForm() throws {
        let poll = try PollParser.poll(in: Fixture.capture("R32a-topic-poll-anon"))
        #expect(poll?.question == "Quelle est votre proportion en superéthanol E85 (période estivale) ?")
        #expect(poll?.maxChoices == 1)
        #expect(poll?.footer == nil)
        let (options, hidden) = try votable(poll)
        #expect(options.map(\.text) == Self.expectedLabels)
        #expect(options.map(\.id) == Array(1...10))
        #expect(options.allSatisfy { $0.fieldName == "reponse" })
        #expect(hidden == [
            "cat": "13", "p": "1", "page": "1", "sondage": "1", "owntopic": "0",
            "subcat": "431", "numeropost": "98162", "hash_check": ""
        ])
    }

    @Test("R32b (logged in, not voted): same form, the token is filled")
    func loggedInVoteForm() throws {
        let anonymous = try PollParser.poll(in: Fixture.capture("R32a-topic-poll-anon"))
        let poll = try PollParser.poll(in: Fixture.capture("R32b-topic-poll-logged-in-not-voted"))
        let (options, hidden) = try votable(poll)
        #expect(options.map(\.text) == Self.expectedLabels)
        #expect(hidden["hash_check"] == "REDACTED")
        var withoutToken = hidden
        var anonymousHidden = try votable(anonymous).hidden
        withoutToken["hash_check"] = nil
        anonymousHidden["hash_check"] = nil
        #expect(withoutToken == anonymousHidden)
        #expect(poll?.question == anonymous?.question)
    }

    @Test(
        "Captured markup facts behind the parser: radio values are the positions, vote form, submit buttons",
        arguments: ["R32a-topic-poll-anon", "R32b-topic-poll-logged-in-not-voted"]
    )
    func markupFacts(name: String) throws {
        let html = try Fixture.capture(name)
        let radio = /<input type="radio" value="([0-9]+)" id="sond[0-9]+" name="reponse" \/>/
        let values = html.matches(of: radio).map { Int($0.output.1) }
        #expect(values == Array(1...10))
        #expect(html.contains("<form method=\"post\" action=\"/user/vote.php?config=hfr.inc\">"))
        #expect(html.contains("<input type=\"submit\" name=\"sondage_submit\" value=\"Voter\" />"))
        #expect(html.contains("<input type=\"submit\" name=\"sondage_submit\" value=\"Voir les résultats\" />"))
        // `hash_check` is printed twice: before `div.sondage` (form level) and inside it; no `verifrequet` (E10/X4).
        let form = try #require(html.firstMatch(of: /<form method="post" action="\/user\/vote.php\?config=hfr.inc">.*?<\/form>/))
        #expect(form.output.matches(of: /name="hash_check"/).count == 2)
        let prefix = "<form method=\"post\" action=\"/user/vote.php?config=hfr.inc\"><input type=\"hidden\" name=\"hash_check\""
        #expect(form.output.hasPrefix(prefix))
        #expect(!form.output.contains("verifrequet"))
    }

    @Test("A page without poll gives nil", arguments: ["R20-topic-p1-anon", "R23-topic-single-page-anon", "R31-topic-locked-anon"])
    func noPoll(name: String) throws {
        #expect(try PollParser.poll(in: Fixture.capture(name)) == nil)
    }

    @Test("A div.sondage fragment alone is accepted; other classes beginning with sondage are not the block")
    func fragmentAndClassTokens() throws {
        let fragment = """
            <div class="sondageLeft">x</div>
            <div class="sondage"><b class="s2">Q ?</b><ol type="1">
            <li><input type="radio" value="1" id="sond1" name="reponse" /><label for="sond1">  A&nbsp;a  </label></li></ol></div>
            """
        let (options, hidden) = try votable(PollParser.poll(in: fragment))
        #expect(options == [PollOption(id: 1, text: "A a", fieldName: "reponse")])
        #expect(hidden.isEmpty)
    }

    @Test("R33a (closed, logged out): results, rank-free labels, total line, closed sentence")
    func closedPoll() throws {
        let page = try PollParser.poll(in: Fixture.capture("R33a-topic-poll-closed-anon"))
        let poll = try #require(page)
        #expect(poll.question == "Ils l'ont tous embrassé mais c'est lui qui la tient, c'est lui qui la soulève...")
        #expect(poll.footer == "Total : 194 votes (16 votes blancs)")
        #expect(poll.notice == "Ce sondage est clos, vous ne pouvez plus voter")
        #expect(poll.maxChoices == 1)
        guard case .results(let lines) = poll.kind else {
            Issue.record("Expected results")
            return
        }
        #expect(lines == [
            PollResult(id: 1, label: "Hugo Lloris", percentage: 65.2, voteCount: 116),
            PollResult(id: 2, label: "Lionel Messi", percentage: 10.1, voteCount: 18),
            PollResult(id: 3, label: "Trifon", percentage: 24.7, voteCount: 44)
        ])
    }

    @Test("R33b (already voted, multi-pseudo notice): results and the notice inside the block")
    func votedPoll() throws {
        let page = try PollParser.poll(in: Fixture.capture("R33b-topic-poll-already-voted"))
        let poll = try #require(page)
        #expect(poll.question == "Allez-vous acheter l'iPhone Ultra ?")
        #expect(poll.notice == "(Multipseudo detecté, vous ne pourrez pas voter à ce sondage avec vos autres pseudos)")
        #expect(poll.footer == "Total : 89 votes (5 votes blancs)")
        guard case .results(let lines) = poll.kind else {
            Issue.record("Expected results")
            return
        }
        #expect(lines.map(\.label) == ["Oui", "Non", "Obiwan"])
        #expect(lines.map(\.percentage) == [33.3, 52.4, 14.3])
        #expect(lines.map(\.voteCount) == [28, 44, 12])
    }

    @Test("Result markup facts: bar, percentage, closed sentence, no vote form")
    func resultFacts() throws {
        let html = try Fixture.capture("R33a-topic-poll-closed-anon")
        let bar = "<div class=\"barre\" style=\"width:80%\">&nbsp;</div>"
        let top = "<div style=\"position:absolute;left:0px\" class=\"sondageTop\">65.2&nbsp;%</div>"
        #expect(html.contains(bar + top))
        #expect(html.contains("<b class=\"s1Ext\">Ce sondage est clos, vous ne pouvez plus voter</b>"))
        #expect(!html.contains("action=\"/user/vote.php"))
    }

    @Test("A decimal comma and bad numbers in the bars")
    func decimalComma() throws {
        func page(_ top: String, right: String = "<div class=\"sondageRight\">1.&nbsp; A</div>") -> String {
            """
            <div class="sondage"><b class="s2">Q ?</b><div class="sondageLeft"><div class="sondageTop">\(top)</div>\
            <div class="sondageTop">&nbsp;3 votes</div></div>\(right)</div>
            """
        }
        guard case .results(let lines)? = try PollParser.poll(in: page("16,7&nbsp;%"))?.kind else {
            Issue.record("Expected results")
            return
        }
        #expect(lines.first?.percentage == 16.7)
        for bad in ["abc", "101&nbsp;%"] {
            #expect(throws: ParsingError.invalidValue(field: "poll results")) { try PollParser.poll(in: page(bad)) }
        }
        #expect(throws: ParsingError.invalidValue(field: "poll results")) { try PollParser.poll(in: page("5 %", right: "")) }
    }

    @Test("Shapes not proven by a capture are typed errors, not guesses")
    func pendingStates() {
        let empty = "<div class=\"sondage\"><b class=\"s2\">Q ?</b></div>"
        #expect(throws: ParsingError.missingElement("poll answers or results in poll block")) { try PollParser.poll(in: empty) }
        let checkbox = """
            <div class="sondage"><b class="s2">Q ?</b><ol><li><input type="checkbox" name="reponse1"><label>A</label></li></ol></div>
            """
        #expect(throws: ParsingError.invalidValue(field: "poll answer input type")) { try PollParser.poll(in: checkbox) }
        let rowWithoutInput = """
            <div class="sondage"><b class="s2">Q ?</b><ol><li><input type="radio" value="1" name="reponse"><label>A</label></li>
            <li>B</li></ol></div>
            """
        #expect(throws: ParsingError.missingElement("input in poll answer")) { try PollParser.poll(in: rowWithoutInput) }
        let noQuestion = "<div class=\"sondage\"><ol><li><input type=\"radio\" name=\"reponse\"><label>A</label></li></ol></div>"
        #expect(throws: ParsingError.missingElement("class~=s2")) { try PollParser.poll(in: noQuestion) }
    }

    @Test(
        "A radio value that is not its position is refused",
        arguments: ["value=\"3\" id=\"sond2\"", "value=\"2x\" id=\"sond2\"", "value=\"0\" id=\"sond2\"", "id=\"sond2\""]
    )
    func radioValueMustBePosition(replacement: String) throws {
        let html = try Fixture.capture("R32b-topic-poll-logged-in-not-voted")
        let original = "value=\"2\" id=\"sond2\""
        #expect(html.contains(original))
        let mutated = html.replacing(original, with: replacement)
        #expect(throws: ParsingError.invalidValue(field: "poll answer value")) { try PollParser.poll(in: mutated) }
    }

    @Test("The poll's description never prints the token")
    func tokenIsNotPrinted() throws {
        let page = try PollParser.poll(in: Fixture.capture("R32b-topic-poll-logged-in-not-voted"))
        let poll = try #require(page)
        #expect(!String(describing: poll).contains("REDACTED"))
    }
}
