import HFRStorage

/// One option of Réglages › Expérimental (#903): modern code kept behind a switch while the default build keeps the legacy
/// behaviour. Removing an option means deleting its case, its folder `Experimental/<Option>/` and the marker comments that
/// name it (AGENTS.md §7: `git grep` lists every one).
enum ExperimentalFeature: String, CaseIterable, Identifiable, Sendable {
    case modernComposer
    case searchTab
    case mpStorageSwitches
    case flagIconRows
    case imageLoadingChoice

    var id: Self { self }

    /// The option's device key (ADR 0013 matrix E, Device-only).
    var setting: Setting<Bool> {
        switch self {
        case .modernComposer: SettingKey.experimentalModernComposer
        case .searchTab: SettingKey.experimentalSearchTab
        case .mpStorageSwitches: SettingKey.experimentalMPStorageSwitches
        case .flagIconRows: SettingKey.experimentalFlagIconRows
        case .imageLoadingChoice: SettingKey.experimentalImageLoadingChoice
        }
    }

    /// The issue that owns the option.
    var issue: Int {
        switch self {
        case .modernComposer: 904
        case .searchTab: 896
        case .mpStorageSwitches: 859
        case .flagIconRows: 905
        case .imageLoadingChoice: 902
        }
    }

    /// Listed in Réglages only once its switch changes something: an option whose path is not built yet is hidden, so there is
    /// no dead switch, and reads as its default whatever the store holds. `flagIconRows` waits for #817's legacy rows (its two
    /// paths look the same until then); the others wait for their own PR.
    var isListed: Bool {
        switch self {
        case .modernComposer, .mpStorageSwitches: true
        case .searchTab, .flagIconRows, .imageLoadingChoice: false
        }
    }

    /// The sub-menu that lists it.
    var theme: ExperimentalTheme {
        switch self {
        case .modernComposer: .composer
        case .searchTab: .navigation
        case .mpStorageSwitches: .messages
        case .flagIconRows: .lists
        case .imageLoadingChoice: .imageLoading
        }
    }

    /// The switch's label.
    var title: String {
        switch self {
        case .modernComposer: "Composer moderne"
        case .searchTab: "Recherche dans la barre"
        case .mpStorageSwitches: "Stockage MP détaillé"
        case .flagIconRows: "Lignes avec icônes de drapeau"
        case .imageLoadingChoice: "Chargement des images"
        }
    }

    /// What the switch changes, shown under the ⓘ and read by VoiceOver.
    var explanation: String {
        switch self {
        case .modernComposer:
            "Sur iPhone, le composer s’ouvre en carte compacte posée sur le clavier, la page restant visible au-dessus, avec des "
                + "boutons flottants. Désactivé : le composer s’ouvre en pleine hauteur, avec la barre et les boutons classiques."
        case .searchTab:
            "Ajoute un onglet Recherche à gauche de Plus (cinq onglets). Désactivé : la barre à quatre onglets de l’app historique."
        case .mpStorageSwitches:
            "Un interrupteur par fonction du stockage MP : liste noire partagée, favoris de messages, MP multiples. Désactivé : "
                + "un seul interrupteur « Activer le stockage MP »."
        case .flagIconRows:
            "Un point devant les sujets non lus et une icône de drapeau devant le titre. Désactivé : la ligne entière teintée "
                + "selon le drapeau, comme l’app historique."
        case .imageLoadingChoice:
            "Choisir quand charger les images : Jamais, Wi-Fi uniquement ou Toujours. Désactivé : les images se chargent "
                + "toujours, comme l’app historique."
        }
    }
}

/// A sub-menu of Réglages › Expérimental, in display order.
enum ExperimentalTheme: String, CaseIterable, Identifiable, Sendable {
    case composer
    case navigation
    case lists
    case messages
    case imageLoading

    var id: Self { self }

    /// The sub-menu's row label.
    var title: String {
        switch self {
        case .composer: "Composer"
        case .navigation: "Barre d’onglets"
        case .lists: "Listes"
        case .messages: "Messages"
        case .imageLoading: "Chargement des images"
        }
    }

    /// The row's symbol.
    var symbol: String {
        switch self {
        case .composer: "square.and.pencil"
        case .navigation: "dock.rectangle"
        case .lists: "list.bullet"
        case .messages: "envelope"
        case .imageLoading: "photo"
        }
    }

    /// The listed options of this sub-menu, in enum order.
    var listedFeatures: [ExperimentalFeature] {
        ExperimentalFeature.allCases.filter { $0.theme == self && $0.isListed }
    }

    /// The sub-menus that list at least one option: an empty one is not shown.
    static var listed: [ExperimentalTheme] { allCases.filter { !$0.listedFeatures.isEmpty } }
}
