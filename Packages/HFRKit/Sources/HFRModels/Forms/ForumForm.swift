/// The `<form name="hop">` HFR serves for replies, edits, new topics and private messages (and the moderation variant).
public struct ForumForm: Sendable, Hashable, Codable {
    /// The form `action`, as served (never assume `bddpost.php`; the edit form's action is unverified).
    public var action: String?
    /// Inputs in page order.
    public var fields: [FormField]
    /// Selects in page order.
    public var selects: [FormSelect]
    /// Entity-decoded content of the `content_form` textarea (quote or edit prefill); nil when the form has none.
    public var textareaContent: String?
    /// Favourite smileys listed in `#dynamic_smilies`.
    public var dynamicSmileys: [ForumSmiley]

    /// Creates a form.
    public init(
        action: String? = nil,
        fields: [FormField] = [],
        selects: [FormSelect] = [],
        textareaContent: String? = nil,
        dynamicSmileys: [ForumSmiley] = []
    ) {
        self.action = action
        self.fields = fields
        self.selects = selects
        self.textareaContent = textareaContent
        self.dynamicSmileys = dynamicSmileys
    }

    /// First input with this name.
    public func field(named name: String) -> FormField? {
        fields.first { $0.name == name }
    }

    /// First select with this name.
    public func select(named name: String) -> FormSelect? {
        selects.first { $0.name == name }
    }

    /// True when the form shows a visible `sujet` input (new topic, new private message).
    public var isSubjectEditable: Bool {
        field(named: "sujet").map { $0.kind != .hidden } ?? false
    }

    /// True when the form offers a `subcat` select.
    public var isSubcategoryEditable: Bool {
        select(named: "subcat") != nil
    }

    /// Options of the `subcat` select; empty when there is none.
    public var subcategories: [FormOption] {
        select(named: "subcat")?.options ?? []
    }

    /// Value of the `dest` (recipient) input, when present.
    public var recipient: String? {
        field(named: "dest")?.value
    }
}
