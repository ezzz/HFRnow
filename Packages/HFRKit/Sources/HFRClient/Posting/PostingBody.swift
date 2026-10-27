import HFRModels
import HFRNetwork
import HFRParsing

/// Builds the body of a write the way a browser submits the `hop` form (HTML form submission rules), pure.
///
/// Walks the controls in document order (`HopFormLayout`), so the fields come in the order of every captured write
/// (`request_fields` of `W10`-`W20b`). A browser sends a text, hidden or password input with its value, a checkbox or
/// radio only when checked, the clicked submit button only (the form has one, `submit`), a select's selected option
/// (else the first), a textarea's text; it skips disabled controls, controls without a name and unclicked buttons.
/// Legacy sent every checkbox as `"1"`/`"0"` (`QuoteMessageViewController.m:209-290`); HFR reads the value, so both
/// work (`W13b` vs `W11`, HFR-PROTOCOL §6b "Checkbox values"), and browser semantics never send `delete=0` to an edit.
enum PostingBody {
    /// The fields to send.
    /// - Parameters:
    ///   - text: the message, written into `content_form`; line breaks are sent as CRLF, like a browser.
    ///   - overrides: new values of text, hidden or password inputs and of selects, by name (`sujet`, `dest`, `subcat`).
    ///   - checkboxes: boxes to check or uncheck, by name; the others keep the form's state.
    /// - Throws: `unsupportedForm` when the form holds a control that cannot be sent like a browser, when it has no
    ///   `content_form` textarea or no `verifrequet` (every write carries it, HFR-PROTOCOL §7 X4), or when the layout
    ///   does not match the parsed form.
    static func make(
        form: ForumForm,
        layout: HopFormLayout,
        text: String,
        overrides: [String: String] = [:],
        checkboxes: [String: Bool] = [:]
    ) throws(PostingError) -> FormBody {
        try check(form: form, layout: layout)
        var body = FormBody(newlines: .crlf)
        var submitted = false
        for control in layout.controls {
            switch control {
            case let .input(index, name, isDisabled):
                guard !isDisabled, !name.isEmpty else { continue }
                let field = form.fields[index]
                // Only the first submit button is "clicked"; later ones stay out like any unclicked button.
                if field.kind == .submit, submitted { continue }
                submitted = submitted || field.kind == .submit
                if let value = try value(of: field, overrides: overrides, checkboxes: checkboxes) { body.append(name, value) }
            case let .select(index, name, isDisabled):
                guard !isDisabled, !name.isEmpty else { continue }
                if let value = overrides[name] ?? form.selects[index].effectiveValue { body.append(name, value) }
            case let .textarea(name, isDisabled):
                guard !isDisabled, !name.isEmpty else { continue }
                guard name == contentField else { throw .unsupportedForm(reason: "textarea \(name)") }
                body.append(name, text)
            case .button:
                continue
            }
        }
        return body
    }

    /// What a browser sends for one input, nil when it sends nothing. A checkbox sends its `value` attribute; none of the
    /// captured boxes lacks one (a browser would send `on`, which `FormField` cannot tell from an empty value).
    private static func value(
        of field: FormField,
        overrides: [String: String],
        checkboxes: [String: Bool]
    ) throws(PostingError) -> String? {
        switch field.kind {
        case .checkbox:
            (checkboxes[field.name] ?? field.isChecked) ? field.value : nil
        case .radio:
            field.isChecked ? field.value : nil
        case .submit:
            field.value
        case .text, .hidden, .password:
            overrides[field.name] ?? field.value
        case .other:
            throw .unsupportedForm(reason: "input type of \(field.name)")
        }
    }

    static let contentField = "content_form"
    static let requestCheckField = "verifrequet"

    /// The layout must describe the same inputs and selects as the parsed form, in the same order, and the form must
    /// hold the fields every captured write carries.
    private static func check(form: ForumForm, layout: HopFormLayout) throws(PostingError) {
        var inputNames: [String] = []
        var selectNames: [String] = []
        var hasContent = false
        for control in layout.controls {
            switch control {
            case let .input(index, name, _):
                guard index == inputNames.count else { throw .unsupportedForm(reason: "layout") }
                inputNames.append(name)
            case let .select(index, name, _):
                guard index == selectNames.count else { throw .unsupportedForm(reason: "layout") }
                selectNames.append(name)
            case let .textarea(name, isDisabled):
                hasContent = hasContent || (name == contentField && !isDisabled)
            case .button:
                continue
            }
        }
        guard inputNames == form.fields.map(\.name), selectNames == form.selects.map(\.name) else {
            throw .unsupportedForm(reason: "layout")
        }
        guard hasContent else { throw .unsupportedForm(reason: "no \(contentField)") }
        guard form.field(named: requestCheckField) != nil else { throw .unsupportedForm(reason: "no \(requestCheckField)") }
    }
}
