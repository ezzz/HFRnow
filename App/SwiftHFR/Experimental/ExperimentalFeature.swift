import HFRStorage

/// One option of Réglages › Expérimental (#903): modern code kept behind a switch while the default build keeps the legacy
/// behaviour. Removing an option means deleting its case, its folder `Experimental/<Option>/` and the marker comments that
/// name it (AGENTS.md §7: `git grep` lists every one).
enum ExperimentalFeature: String, CaseIterable, Identifiable, Sendable {
    // Declared in the order of the page's sections (`ExperimentalTheme`): the page lists them by theme, and a test checks this order.
    case modernComposer
    case searchTab
    case denseRows
    case mpDarkTopic
    case imageLoadingChoice

    var id: Self { self }

    /// The option's device key (ADR 0013 matrix E, Device-only).
    var setting: Setting<Bool> {
        switch self {
        case .modernComposer: SettingKey.experimentalModernComposer
        case .searchTab: SettingKey.experimentalSearchTab
        case .mpDarkTopic: SettingKey.experimentalMPDarkTopic
        case .denseRows: SettingKey.experimentalDenseRows
        case .imageLoadingChoice: SettingKey.experimentalImageLoadingChoice
        }
    }

    /// The issue that owns the option.
    var issue: Int {
        switch self {
        case .modernComposer: 904
        case .searchTab: 896
        case .mpDarkTopic: 1014
        case .denseRows: 905
        case .imageLoadingChoice: 902
        }
    }

    /// The section that lists it.
    var theme: ExperimentalTheme {
        switch self {
        case .modernComposer: .composer
        case .searchTab: .navigation
        case .mpDarkTopic: .messages
        case .denseRows: .lists
        case .imageLoadingChoice: .imageLoading
        }
    }

    /// The switch's label.
    var title: String {
        switch self {
        case .modernComposer: "Composer moderne"
        case .searchTab: "Recherche dans la barre"
        case .mpDarkTopic: MPDarkTopic.title
        case .denseRows: "Lignes denses"
        case .imageLoadingChoice: "Chargement des images"
        }
    }

    /// Whether the explanation is always shown under the switch, with no ⓘ (operator, 2026-11-17, #1014), instead of behind it.
    var showsExplanationUnderSwitch: Bool { self == .mpDarkTopic }

    /// What the switch changes, shown under the ⓘ (or under the switch, `showsExplanationUnderSwitch`) and read by VoiceOver.
    var explanation: String {
        switch self {
        case .modernComposer:
            "Sur iPhone, le composer s’ouvre en carte compacte posée sur le clavier, la page restant visible au-dessus, avec des "
                + "boutons flottants. Désactivé : le composer s’ouvre en plein écran, comme l’app historique."
        case .searchTab:
            "Ajoute un onglet Recherche à gauche de Plus (cinq onglets). Désactivé : la barre à quatre onglets de l’app historique."
        case .mpDarkTopic: MPDarkTopic.explanation
        case .denseRows:
            "Sujets et MP sur des lignes denses : point et icône de drapeau devant le titre, dernier posteur, ligne d’infos sur "
                + "une seule ligne, sans « il y a » ni nombre de réponses, titres de section en gras. Désactivé : les lignes de l’app "
                + "historique (pas de point ni d’icône devant le titre)."
        case .imageLoadingChoice:
            "Ajoute un choix du moment où charger les images : Toujours, Wi-Fi uniquement ou Jamais (au toucher). Désactivé : "
                + "les images se chargent toujours, comme l’app historique."
        }
    }
}

/// A section of the Réglages › Expérimental page, in display order.
enum ExperimentalTheme: String, CaseIterable, Identifiable, Sendable {
    case composer
    case navigation
    case lists
    case messages
    case imageLoading

    var id: Self { self }

    /// The section's header.
    var title: String {
        switch self {
        case .composer: "Composer"
        case .navigation: "Barre d’onglets"
        case .lists: "Listes"
        case .messages: "Messages"
        case .imageLoading: "Chargement des images"
        }
    }

    /// The listed options of this section, in enum order.
    var listedFeatures: [ExperimentalFeature] {
        ExperimentalFeature.allCases.filter { $0.theme == self }
    }

    /// The sections that list at least one option: an empty one is not shown.
    static var listed: [ExperimentalTheme] { allCases.filter { !$0.listedFeatures.isEmpty } }
}
