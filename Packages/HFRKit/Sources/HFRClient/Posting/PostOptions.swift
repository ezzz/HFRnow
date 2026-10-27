/// The three option boxes of the composer; nil keeps the box as the form serves it.
public struct PostOptions: Sendable, Equatable {
    /// "Activer votre signature" (field `signature`).
    public var signature: Bool?
    /// "Désactiver les smilies" (field `smiley`): HFR reads a sent `smiley=1` as "do not render smileys" (`W13b`, `RA3`).
    public var disablesSmileys: Bool?
    /// "Activer la notification par email du sujet" (field `emaill`).
    public var emailNotification: Bool?

    /// Creates options; every box defaults to the form's own state.
    public init(signature: Bool? = nil, disablesSmileys: Bool? = nil, emailNotification: Bool? = nil) {
        self.signature = signature
        self.disablesSmileys = disablesSmileys
        self.emailNotification = emailNotification
    }

    /// The boxes to force, by form field name.
    var checkboxes: [String: Bool] {
        var boxes: [String: Bool] = [:]
        boxes["signature"] = signature
        boxes["smiley"] = disablesSmileys
        boxes["emaill"] = emailNotification
        return boxes
    }
}
