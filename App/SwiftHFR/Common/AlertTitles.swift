/// The titles of the error and question alerts (#1175, HIG › Alerts: a title says what failed or what is asked,
/// never « Erreur »).
/// Constants so a test pins them; the detail stays in each alert's message.
enum AlertTitles {
    /// A pseudo could not be added to the blocklist or the whitelist.
    static let pseudoAddFailed = "Ajout impossible"
    /// The pseudo typed is already in the list (nothing failed, nothing was added).
    static let pseudoAlreadyListed = "Pseudo déjà dans la liste"
    /// A pseudo could not be removed from the list.
    static let pseudoRemoveFailed = "Suppression impossible"
    /// The unreadable lists could not be set aside (« Repartir de zéro »).
    static let listResetFailed = "Réinitialisation impossible"
    /// The app icon did not change.
    static let iconChangeFailed = "Changement d’icône impossible"
    /// The account selected did not become the current one.
    static let accountSwitchFailed = "Changement de compte impossible"
    /// The account could not be removed from the app.
    static let accountRemoveFailed = "Retrait du compte impossible"
    /// « Marquer comme non lu » was not confirmed by the forum.
    static let markUnreadFailed = "Marquage comme non lu impossible"
    /// A favourite flag could not be removed (« Supprimer » on a favourites row).
    static let flagRemoveFailed = "Suppression du drapeau impossible"
    /// The first blocklist write of an account that never chose: sync it with MPStorage?
    static let blocklistSyncQuestion = "Synchroniser la liste noire ?"
    /// The first bookmark of an account that never chose: switch MPStorage on?
    static let mpStorageQuestion = "Activer le stockage MP ?"
    /// « Non » to the MPStorage creation question: confirm going on without it?
    static let mpStorageRefusalQuestion = "Continuer sans stockage MP ?"
    /// The first image upload: send images to the host?
    static let imageHostQuestion = "Envoyer les images à l’hébergeur ?"
    /// The first GIF search: go through Giphy?
    static let gifServiceQuestion = "Chercher des GIF via Giphy ?"
    /// The first Alerte Qualitay of an account that never accepted the notice: publish it?
    static let qualityNoticeQuestion = "Publier sur Alertes Qualitay ?"
    /// The message is already reported: add it to that alert?
    static let qualityAdditionQuestion = "Plussoyer l’alerte existante ?"
}
