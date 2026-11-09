/// The composer's text fields, in the order a new private message visits them.
enum ComposerField: Hashable {
    case recipient, subject, text
}

/// When the formatting bar may act, and where focus goes after it did (#599).
///
/// Every bar action edits the text: while the recipient or subject field has focus, a tap would insert into a text the member
/// is not looking at and move focus (and the keyboard, whose height differs between fields) to the editor. So the bar is off
/// while another field has focus and on otherwise. "No field" stays on, as before #599, so a reply whose keyboard went away
/// (a sheet took focus and closed without inserting) keeps a working bar: a tap brings focus back to the text.
enum ComposerBarFocus {
    /// Whether the bar's buttons may act with this field focused.
    static func allowsBar(focused: ComposerField?) -> Bool {
        switch focused {
        case .text, nil: true
        case .recipient, .subject: false
        }
    }

    /// Focus after a bar action: the text when it had focus or nothing had, else unchanged (never taken from another field).
    static func focus(afterBarActionFrom focused: ComposerField?) -> ComposerField? {
        allowsBar(focused: focused) ? .text : focused
    }
}
