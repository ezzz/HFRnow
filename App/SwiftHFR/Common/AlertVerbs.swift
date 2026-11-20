/// The button titles of the confirmation alerts (#1151, HIG: a button names its action, never « Oui » / « Non »). Constants so a
/// test pins them; the alerts keep their roles (cancel, destructive) as before.
enum AlertVerbs {
    /// Dismisses the question, nothing happens.
    static let cancel = "Annuler"
    /// « Supprimer ce message ? » (destructive).
    static let deleteMessage = "Supprimer"
    /// « Alerter les modérateurs par email ? ».
    static let prepareModeratorMail = "Préparer l’email"
    /// « Revenir à l’icône précédente ? ».
    static let revertSeasonalIcon = "Revenir"
    /// The other answer to that question (cancel).
    static let keepIcon = "Garder"
    /// « Sans stockage MP » (destructive): no MP storage is created.
    static let skipMPStorage = "Ne pas créer"
}
