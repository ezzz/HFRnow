import Foundation
import HFRModels
import SwiftSoup

/// Reads the poll of a topic page (HFR-PROTOCOL §3.1 "Poll vote", E10, §6c "LOT-026 — poll").
///
/// Two states are proven by captures and handled:
/// - the **voting form** (`R32a` logged out, `R32b` logged in, not voted): `<div class="sondage">` inside
///   `<form method="post" action="/user/vote.php?config=hfr.inc">`, radio answers;
/// - the **results** (`R33a` closed poll, `R33b` already voted): the same block with `div.sondageLeft` bars
///   (percentage and vote count) each followed by a `div.sondageRight` label, and a "Total" line.
///
/// A plain "already voted" page without the multi-pseudo notice and multi-choice polls were not captured; their shapes are
/// refused with a typed error instead of being guessed (see `docs/lots/LOT-026-poll-parser.md`, "Pending").
/// Legacy took the first element whose class is exactly `sondage` (`ObjCTopicPageWorker.m:159-162`) and parsed it with
/// regexes (`PollData.swift:104-355`).
public enum PollParser {
    /// The poll of a topic page or of a `div.sondage` fragment; nil when the page has no `div.sondage`.
    ///
    /// Mode rule (captures): answer rows (`li` with a radio) make a voting form, otherwise `div.sondageLeft` bars make results.
    /// - `question`: text of the `s2` element, whitespace collapsed.
    /// - Voting form: `id` = 1-based position, required to equal the radio `value`; `fieldName` = the input `name`;
    ///   `hiddenFields` = every `input[type=hidden]` inside the block. `footer` and `notice` are nil.
    /// - Results: one line per bar, `id` = position, `label` without the printed "N." prefix, `percentage` (decimal point or
    ///   comma) and `voteCount`. `footer` = the "Total : N votes (M votes blancs)" line, `notice` = the text HFR adds: the
    ///   multi-pseudo notice inside the block, or the "Ce sondage est clos…" line that follows it.
    /// - `maxChoices` is 1: no capture shows a multi-choice hint.
    /// - Throws: `missingElement` when the block has no question and neither answers nor bars, `invalidValue` when an answer is
    ///   not a radio or its `value` is not its position, or when bars and labels do not pair up or a percentage is out of range.
    public static func poll(in html: String) throws(ParsingError) -> Poll? {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let block = document.firstDescendant(matching: .classToken("sondage")) else { return nil }
        let question = try block.requiredDescendant(matching: .classToken("s2"))
        let text = cleanedText(of: question)
        if hasAnswerRows(block) {
            let options = try options(in: block)
            return Poll(question: text, kind: .votable(options: options, hiddenFields: hiddenFields(in: block)))
        }
        let lines = try resultLines(in: block)
        return Poll(question: text, footer: totalLine(in: block), notice: notice(of: block), kind: .results(lines))
    }

    // MARK: - Voting form

    private static func hasAnswerRows(_ block: Element) -> Bool {
        descendants(tagged: "li", in: block).contains { !descendants(tagged: "input", in: $0).isEmpty }
    }

    /// Answer rows: `<li><input type="radio" value="N" id="sondN" name="reponse"><label for="sondN">text</label></li>`.
    private static func options(in block: Element) throws(ParsingError) -> [PollOption] {
        var options: [PollOption] = []
        for row in descendants(tagged: "li", in: block) {
            guard let input = descendants(tagged: "input", in: row).first else { throw .missingElement("input in poll answer") }
            guard (try? input.attr("type"))?.lowercased() == "radio" else { throw .invalidValue(field: "poll answer input type") }
            let name = try input.requiredAttribute("name")
            guard let label = descendants(tagged: "label", in: row).first else { throw .missingElement("label in poll answer") }
            // The server receives the radio `value`, so it must be the position the model advertises as `id`.
            let position = options.count + 1
            guard let value = try? input.attr("value"), HFRURL.positiveInteger(value) == position else {
                throw .invalidValue(field: "poll answer value")
            }
            options.append(PollOption(id: position, text: cleanedText(of: label), fieldName: name))
        }
        return options
    }

    /// `name` to `value` of the hidden inputs of the block; a repeated name keeps the last value, as legacy.
    private static func hiddenFields(in block: Element) -> [String: String] {
        var fields: [String: String] = [:]
        for input in descendants(tagged: "input", in: block) where (try? input.attr("type"))?.lowercased() == "hidden" {
            guard let name = try? input.attr("name"), !name.isEmpty else { continue }
            fields[name] = (try? input.attr("value")) ?? ""
        }
        return fields
    }

    // MARK: - Results

    /// Bars: `div.sondageLeft` (two `div.sondageTop`: percentage, then votes) immediately followed by `div.sondageRight` (label).
    /// Legacy paired the two lists by index and cut the longer one (`PollData.swift:253-269`); a mismatch is an error here.
    private static func resultLines(in block: Element) throws(ParsingError) -> [PollResult] {
        let bars = block.descendants(matching: .classToken("sondageLeft"))
        guard !bars.isEmpty else { throw .missingElement("poll answers or results in poll block") }
        var lines: [PollResult] = []
        for bar in bars {
            let tops = bar.descendants(matching: .classToken("sondageTop"))
            guard
                tops.count >= 2,
                let label = try? bar.nextElementSibling(),
                label.hasClass("sondageRight"),
                let percentage = percentage(in: cleanedText(of: tops[0])),
                let votes = HFRText.firstInteger(in: cleanedText(of: tops[1]))
            else { throw .invalidValue(field: "poll results") }
            lines.append(PollResult(
                id: lines.count + 1,
                label: labelWithoutRank(cleanedText(of: label)),
                percentage: percentage,
                voteCount: votes
            ))
        }
        guard block.descendants(matching: .classToken("sondageRight")).count == lines.count else {
            throw .invalidValue(field: "poll results")
        }
        return lines
    }

    /// First number of "65.2 %", with a decimal point or comma (legacy read only the point, `PollData.swift:330`); 0...100.
    private static func percentage(in text: String) -> Double? {
        guard let match = text.firstMatch(of: /[0-9]+(?:[.,][0-9]+)?/) else { return nil }
        guard let value = Double(match.output.replacing(",", with: ".")), (0...100).contains(value) else { return nil }
        return value
    }

    /// "1. Hugo Lloris" to "Hugo Lloris": the rank is the `id`.
    private static func labelWithoutRank(_ label: String) -> String {
        guard let match = label.prefixMatch(of: /[0-9]+\.\s*/) else { return label }
        return String(label[match.range.upperBound...])
    }

    /// The `<div><b>Total : 194 votes</b>&nbsp;(16 votes blancs)</div>` line closing the block.
    private static func totalLine(in block: Element) -> String? {
        block.children().array().last { child in
            child.tagName() == "div" && !child.hasAttr("class") && cleanedText(of: child).hasPrefix("Total")
        }.map(cleanedText(of:))
    }

    /// Text directly inside the block (the multi-pseudo notice, `R33b`), else the `b.s1Ext` that follows it (`R33a`).
    private static func notice(of block: Element) -> String? {
        let inside = block.textNodes().map { cleanedText($0.text()) }.filter { !$0.isEmpty }.joined(separator: " ")
        if !inside.isEmpty { return inside }
        if let next = try? block.nextElementSibling(), next.hasClass("s1Ext") {
            let text = cleanedText(of: next)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    // MARK: - Helpers

    private static func descendants(tagged tag: String, in element: Element) -> [Element] {
        ((try? element.getElementsByTag(tag))?.array() ?? []).filter { $0 !== element }
    }

    private static func cleanedText(of element: Element) -> String {
        cleanedText((try? element.text()) ?? "")
    }

    /// Non-breaking spaces turned into spaces and runs of whitespace collapsed (legacy `cleanedPollText`).
    private static func cleanedText(_ text: String) -> String {
        text.replacing("\u{00A0}", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
