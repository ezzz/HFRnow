/// An option box of the composer; a write takes the boxes to force as `[PostOption: Bool]`, the others keep the form's
/// state.
public enum PostOption: String, Sendable, Hashable, CaseIterable {
    /// "Activer votre signature".
    case signature
    /// "Désactiver les smilies": HFR reads a sent `smiley=1` as "do not render smileys" (`W13b`, `RA3`).
    case disablesSmileys = "smiley"
    /// "Activer la notification par email du sujet".
    case emailNotification = "emaill"

    /// The form field name.
    var fieldName: String { rawValue }
}
