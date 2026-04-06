//
//  PollData.swift
//  HFRswift
//
//  Models, HTML parser, and vote submitter for HFR topic polls.
//

import Foundation

// MARK: - Models

struct PollOption: Identifiable {
    let id: Int          // 1-based
    let text: String
    let fieldName: String
}

struct PollResult: Identifiable {
    let id: Int          // 1-based
    let label: String
    let percentage: Double   // e.g. 16.7
    let voteCount: Int
}

struct PollData: Identifiable {
    var id: String { question }
    let question: String
    let footer: String
    let maxChoices: Int
    let options: [PollOption]
    let results: [PollResult]
    let hiddenFields: [String: String]

    var isVotable: Bool { !options.isEmpty }
    var hasResults: Bool { !results.isEmpty }
}

// MARK: - Vote Submission

enum PollVoteSubmitResult {
    case success
    case error(String)
}

enum PollVoteSubmitter {
    private static let voteURL = "https://forum.hardware.fr/user/vote.php?config=hfr.inc"

    static func submit(pollData: PollData, selectedIndices: Set<Int>) async -> PollVoteSubmitResult {
        var params: [String: String] = pollData.hiddenFields

        for index in selectedIndices {
            guard let option = pollData.options.first(where: { $0.id == index }) else { continue }
            if pollData.maxChoices == 1 {
                params[option.fieldName] = "\(index)"
            } else {
                params[option.fieldName] = "1"
            }
        }

        guard let url = URL(string: voteURL) else { return .error("URL invalide") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key.percentEncoded)=\($0.value.percentEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            return parseVoteResponse(html)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func parseVoteResponse(_ html: String) -> PollVoteSubmitResult {
        // The response contains a <div class="hop"> element.
        // If it contains <a or <input, there was an error; otherwise success.
        guard let regex = try? NSRegularExpression(
            pattern: #"<div[^>]+class="hop"[^>]*>(.*?)</div>"#,
            options: .dotMatchesLineSeparators
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) else {
            return .success
        }

        let content = String(html[range])
        if content.contains("<a") || content.contains("<input") {
            let text = content.strippingPollHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .error(text.isEmpty ? "Erreur lors du vote" : text)
        }
        return .success
    }
}

// MARK: - HTML Parser

enum PollHTMLParser {

    /// Parses poll data from a raw sondage div HTML string (as returned by `swiftPollHTML`).
    static func parse(from sondageHTML: String) -> PollData? {
        guard !sondageHTML.isEmpty else { return nil }

        let question = extractQuestion(from: sondageHTML)
        let footer = extractFooter(from: sondageHTML)
        let maxChoices = extractMaxChoices(from: sondageHTML)

        // Presence of <input> elements means the user can still vote.
        if sondageHTML.range(of: "<input", options: .caseInsensitive) != nil {
            let options = extractOptions(from: sondageHTML)
            let hiddenFields = extractHiddenFields(from: sondageHTML)
            if !options.isEmpty {
                return PollData(
                    question: question,
                    footer: footer,
                    maxChoices: maxChoices,
                    options: options,
                    results: [],
                    hiddenFields: hiddenFields
                )
            }
        }

        // No inputs → show results.
        let results = extractResults(from: sondageHTML)
        if !results.isEmpty {
            return PollData(
                question: question,
                footer: footer,
                maxChoices: maxChoices,
                options: [],
                results: results,
                hiddenFields: [:]
            )
        }

        return nil
    }

    // MARK: - Question

    private static func extractQuestion(from html: String) -> String {
        // HFR uses <b class="s2"> for the question (not <div class="s2">).
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:b|div)\b[^>]+class="s2"[^>]*>(.*?)(?:</b>|</div>)"#,
            options: .dotMatchesLineSeparators
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) else {
            return ""
        }
        return String(html[range]).cleanedPollText()
    }

    // MARK: - Footer

    private static func extractFooter(from html: String) -> String {
        // Try sondageFooter class first.
        if let regex = try? NSRegularExpression(
            pattern: #"<div[^>]+class="sondageFooter[^"]*"[^>]*>(.*?)</div>"#,
            options: .dotMatchesLineSeparators
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) {
            let text = String(html[range])
                .replacing("<br>", with: "\n")
                .replacing("<BR>", with: "\n")
                .strippingPollHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: - Max choices

    private static func extractMaxChoices(from html: String) -> Int {
        // The HTML between </b> and <ol type="1"> contains the multi-choice hint
        // (e.g., "Vous pouvez sélectionner 2 réponses").
        guard let regex = try? NSRegularExpression(
            pattern: #"</b>(.*?)<ol\s+type="1""#,
            options: .dotMatchesLineSeparators
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) else {
            return 1
        }
        let headerText = String(html[range]).strippingPollHTMLTags()
        if let numRegex = try? NSRegularExpression(pattern: #" (\d{1,2}) "#),
           let numMatch = numRegex.firstMatch(in: headerText, range: NSRange(headerText.startIndex..., in: headerText)),
           numMatch.numberOfRanges > 1,
           let numRange = Range(numMatch.range(at: 1), in: headerText),
           let count = Int(headerText[numRange]) {
            return count
        }
        return 1
    }

    // MARK: - Options (voting mode)

    private static func extractOptions(from html: String) -> [PollOption] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<li[^>]*>.*?<input\b[^>]+name="([^"]+)"[^>]*>.*?<label[^>]*>(.*?)</label>.*?</li>"#,
            options: .dotMatchesLineSeparators
        ) else { return [] }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        return matches.enumerated().compactMap { idx, match -> PollOption? in
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { return nil }
            let fieldName = String(html[nameRange])
            let text = String(html[labelRange]).strippingPollHTMLTags()
            return PollOption(id: idx + 1, text: text, fieldName: fieldName)
        }
    }

    // MARK: - Hidden fields

    private static func extractHiddenFields(from html: String) -> [String: String] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: #"<input\b[^>]+type="hidden"[^>]*>"#,
            options: .dotMatchesLineSeparators
        ) else { return [:] }

        let ns = html as NSString
        var fields: [String: String] = [:]

        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            if let name = attrValue("name", in: tag),
               let value = attrValue("value", in: tag) {
                fields[name] = value
            }
        }
        return fields
    }

    // MARK: - Results (already voted / closed)

    private static func extractResults(from html: String) -> [PollResult] {
        // sondageLeft blocks contain two plain <div>N</div> children (percentage, vote count).
        // sondageRight blocks contain the option label.
        // They are interleaved and paired by index.

        let leftPairs = extractSondageLeftPairs(from: html)
        let rightLabels = extractSondageRightLabels(from: html)

        let count = min(leftPairs.count, rightLabels.count)
        return (0..<count).map { i in
            PollResult(
                id: i + 1,
                label: rightLabels[i],
                percentage: leftPairs[i].percentage,
                voteCount: leftPairs[i].voteCount
            )
        }
    }

    private static func extractSondageLeftPairs(from html: String) -> [(percentage: Double, voteCount: Int)] {
        guard let openingRegex = try? NSRegularExpression(
            pattern: #"<div\b[^>]+class="sondageLeft"[^>]*>"#,
            options: .dotMatchesLineSeparators
        ),
        let topRegex = try? NSRegularExpression(
            pattern: #"<div\b[^>]+class="sondageTop"[^>]*>(.*?)</div>"#,
            options: .dotMatchesLineSeparators
        ) else { return [] }

        let ns = html as NSString
        let len = ns.length
        var pairs: [(Double, Int)] = []

        for match in openingRegex.matches(in: html, range: NSRange(location: 0, length: len)) {
            // Extract the full sondageLeft div by counting nesting depth.
            var depth = 1
            var pos = NSMaxRange(match.range)

            while depth > 0 && pos < len {
                let remaining = NSRange(location: pos, length: len - pos)
                let openPos = ns.range(of: "<div", options: [], range: remaining)
                let closePos = ns.range(of: "</div>", options: [], range: remaining)

                if openPos.location != NSNotFound &&
                    (closePos.location == NSNotFound || openPos.location < closePos.location) {
                    depth += 1
                    pos = NSMaxRange(openPos)
                } else if closePos.location != NSNotFound {
                    depth -= 1
                    pos = NSMaxRange(closePos)
                } else {
                    break
                }
            }

            let blockRange = NSRange(location: match.range.location, length: pos - match.range.location)
            let block = ns.substring(with: blockRange)

            // Each sondageLeft contains two sondageTop divs:
            //   first:  "16.7&nbsp;%" → percentage
            //   second: "&nbsp;5 votes" → vote count
            let nsBlock = block as NSString
            let topMatches = topRegex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))
            guard topMatches.count >= 2,
                  let r1 = Range(topMatches[0].range(at: 1), in: block),
                  let r2 = Range(topMatches[1].range(at: 1), in: block) else { continue }

            let pctText = String(block[r1])
            let voteText = String(block[r2])
            let pct = firstDouble(in: pctText) ?? 0.0
            let votes = firstInt(in: voteText) ?? 0
            pairs.append((pct, votes))
        }
        return pairs
    }

    private static func firstDouble(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    private static func firstInt(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func extractSondageRightLabels(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<div\b[^>]+class="sondageRight"[^>]*>(.*?)</div>"#,
            options: .dotMatchesLineSeparators
        ) else { return [] }

        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range]).cleanedPollText()
        }
    }

    // MARK: - Attribute helper

    private static func attrValue(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)=\"([^\"]*)\""),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[range])
    }
}

// MARK: - Private helpers

private extension String {
    /// Strips HTML tags, decodes &nbsp; and collapses whitespace.
    func cleanedPollText() -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return self }
        return regex.stringByReplacingMatches(
            in: self,
            range: NSRange(startIndex..., in: self),
            withTemplate: ""
        )
        .replacing("&nbsp;", with: " ")
        .replacing("  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func strippingPollHTMLTags() -> String { cleanedPollText() }

    var percentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
