import Foundation
import SwiftSoup

/// The controls of a `hop` form in document order: the order in which a browser writes them into the request body.
///
/// `ForumForm` keeps inputs, selects and the textarea in separate lists, which loses where `content_form` and a
/// `<select>` sit among the inputs; every captured write sends them in document order (`request_fields` of `W10`-`W20b`),
/// so the posting flow (LOT-048) walks this list. Indices point into `ForumForm.fields` and `ForumForm.selects` of the
/// same page, and each entry repeats the control's name so a caller can check that both readings agree.
public struct HopFormLayout: Sendable, Hashable {
    /// One named control of the form.
    public enum Control: Sendable, Hashable {
        /// An `<input>`: `index` into `ForumForm.fields`.
        case input(index: Int, name: String, isDisabled: Bool)
        /// A `<select>`: `index` into `ForumForm.selects`.
        case select(index: Int, name: String, isDisabled: Bool)
        /// A `<textarea>` (`content_form` on every captured form).
        case textarea(name: String, isDisabled: Bool)
        /// A `<button name>`: a browser sends it only when it is the one clicked (none in the captures).
        case button(name: String)
    }

    /// Named controls in document order.
    public var controls: [Control]
    /// Text of the `<label for=…>` of each checkbox, by checkbox name (`delete`: "Effacer l'intégralité du sujet" on the
    /// first post of a thread, "Effacer ce message" on a later one, `R43a`, `R43b`).
    public var checkboxLabels: [String: String]

    /// Creates a layout.
    public init(controls: [Control] = [], checkboxLabels: [String: String] = [:]) {
        self.controls = controls
        self.checkboxLabels = checkboxLabels
    }
}

extension HopFormParser {
    /// The layout of the `<form name="hop">` of `html`, read with the same rules as `parse(_:pageURL:)`: an input or a
    /// select counts when it has a `name` attribute (even empty), so `input(index:)` and `select(index:)` line up with
    /// `ForumForm.fields` and `ForumForm.selects` of the same page.
    /// - Throws: `missingElement` when the page has no form named `hop`.
    public static func layout(_ html: String) throws(ParsingError) -> HopFormLayout {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let form = document.descendants(attribute: "name", matching: .exact("hop")).first(where: { $0.tagName() == "form" })
        else {
            throw .missingElement("form name=hop")
        }
        let elements = ((try? form.getAllElements())?.array() ?? []).dropFirst()
        var controls: [HopFormLayout.Control] = []
        var inputs = 0
        var selects = 0
        var checkboxIDs: [String: String] = [:]
        for element in elements where element.hasAttr("name") {
            let name = (try? element.attr("name")) ?? ""
            let isDisabled = element.hasAttr("disabled")
            switch element.tagName() {
            case "input":
                controls.append(.input(index: inputs, name: name, isDisabled: isDisabled))
                inputs += 1
                if (try? element.attr("type"))?.lowercased() == "checkbox", let id = try? element.attr("id"), !id.isEmpty {
                    checkboxIDs[id] = name
                }
            case "select":
                controls.append(.select(index: selects, name: name, isDisabled: isDisabled))
                selects += 1
            case "textarea":
                controls.append(.textarea(name: name, isDisabled: isDisabled))
            case "button":
                controls.append(.button(name: name))
            default:
                continue
            }
        }
        return HopFormLayout(controls: controls, checkboxLabels: labels(in: form, for: checkboxIDs))
    }

    /// Label texts of the checkboxes, matched by the label's `for` and the box's `id` (HFR writes the label after the box).
    private static func labels(in form: Element, for checkboxIDs: [String: String]) -> [String: String] {
        var labels: [String: String] = [:]
        for label in (try? form.getElementsByTag("label"))?.array() ?? [] {
            guard let target = try? label.attr("for"), let name = checkboxIDs[target], labels[name] == nil else { continue }
            labels[name] = label.rawText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return labels
    }
}
