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
        let values = Values(text: text, overrides: overrides, checkboxes: checkboxes)
        var submitted = false
        for control in layout.controls {
            if let entry = try entry(for: control, form: form, values: values, submitted: &submitted) {
                body.append(entry.name, entry.value)
            }
        }
        return body
    }

    /// What the write puts into the form.
    private struct Values {
        let text: String
        let overrides: [String: String]
        let checkboxes: [String: Bool]
    }

    /// The name and value a browser writes for one control, nil when it writes nothing.
    private static func entry(
        for control: HopFormLayout.Control,
        form: ForumForm,
        values: Values,
        submitted: inout Bool
    ) throws(PostingError) -> (name: String, value: String)? {
        switch control {
        case let .input(index, name, isDisabled):
            guard !isDisabled, !name.isEmpty else { return nil }
            let field = form.fields[index]
            // Only the first submit button is "clicked"; later ones stay out like any unclicked button.
            if field.kind == .submit {
                if submitted { return nil }
                submitted = true
            }
            return try value(of: field, overrides: values.overrides, checkboxes: values.checkboxes).map { (name, $0) }
        case let .select(index, name, isDisabled):
            guard !isDisabled, !name.isEmpty else { return nil }
            return (values.overrides[name] ?? form.selects[index].effectiveValue).map { (name, $0) }
        case let .textarea(name, isDisabled):
            guard !isDisabled, !name.isEmpty else { return nil }
            guard name == contentField else { throw .unsupportedForm(reason: "textarea \(name)") }
            return (name, values.text)
        case .button:
            return nil
        }
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
        var inputs: [(index: Int, name: String)] = []
        var selects: [(index: Int, name: String)] = []
        for control in layout.controls {
            switch control {
            case let .input(index, name, _): inputs.append((index, name))
            case let .select(index, name, _): selects.append((index, name))
            case .textarea, .button: continue
            }
        }
        guard
            inputs.map(\.index) == Array(inputs.indices), inputs.map(\.name) == form.fields.map(\.name),
            selects.map(\.index) == Array(selects.indices), selects.map(\.name) == form.selects.map(\.name)
        else { throw .unsupportedForm(reason: "layout") }
        guard layout.controls.contains(.textarea(name: contentField, isDisabled: false)) else {
            throw .unsupportedForm(reason: "no \(contentField)")
        }
        guard form.field(named: requestCheckField) != nil else { throw .unsupportedForm(reason: "no \(requestCheckField)") }
    }
}
