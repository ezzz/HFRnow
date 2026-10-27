import Foundation
import SwiftSoup

/// Text cleaning of the legacy profile parser (`UserProfileView.swift:374-415`): line breaks at `br`, `p` and `div`,
/// no-break spaces as spaces, runs of blanks collapsed, blank lines dropped.
enum UserProfileText {
    /// Cleaned text of an element's content.
    static func clean(_ element: Element) -> String {
        var raw = ""
        append(element, to: &raw)
        return clean(raw)
    }

    /// Cleaned text of a string that may hold line breaks.
    static func clean(_ text: String) -> String {
        text.replacing("\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacing(/[ \t]+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Label of a row: cleaned, without the trailing colon (`cleanTitle`).
    static func cleanTitle(_ element: Element) -> String {
        clean(element).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func append(_ element: Element, to text: inout String) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                text += textNode.getWholeText()
            } else if let child = node as? Element {
                if child.tagName() == "br" {
                    text += "\n"
                    continue
                }
                append(child, to: &text)
                if child.tagName() == "p" || child.tagName() == "div" {
                    text += "\n"
                }
            }
        }
    }
}
