import HFRModels

/// A sub-forum that legacy added by hand next to a sub-forum the home page does list.
///
/// The home page shows only part of the sub-forums of a category; the legacy parser completed the list from a table
/// keyed on the URL of a listed sub-forum (`ObjCForumsParser.m:111-503`). The REST category counts of capture `R57a`
/// confirm the added forums exist (see `docs/lots/LOT-021-forum-list-parser.md`), so the table is kept as data.
struct SubforumInjection: Sendable, Equatable {
    /// Path of the listed sub-forum that triggers the injection (exact match, as legacy).
    let trigger: String
    /// Sub-forums placed just before the trigger.
    let before: [ForumLink]
    /// Sub-forums placed just after the trigger.
    let after: [ForumLink]

    /// Builds a link to a sub-forum topic list from its category slug, forum slug and title.
    private static func link(_ title: String, _ slug: String) -> ForumLink {
        ForumLink(title: title, path: "/hfr/\(slug)/liste_sujet-1.htm")
    }

    /// Every injection, in legacy source order. Legacy has two blocks keyed on `API-Win32` (one before, one after): merged here.
    static let all: [SubforumInjection] = [
        SubforumInjection(
            trigger: "/hfr/Programmation/API-Win32/liste_sujet-1.htm",
            before: [
                link("Divers", "Programmation/Divers-6"),
                link("ADA", "Programmation/ADA"),
                link("Algo", "Programmation/Algo")
            ],
            after: [
                link("ASM", "Programmation/ASM"),
                link("ASP", "Programmation/ASP"),
                link("Biblio Links", "Programmation/BiblioLinks"),
                link("C", "Programmation/C")
            ]
        ),
        after("/hfr/Hardware/minipc/liste_sujet-1.htm", link("Bench", "Hardware/Benchs")),
        after("/hfr/OverclockingCoolingModding/Mod-elec/liste_sujet-1.htm", link("Divers", "OverclockingCoolingModding/Divers-8")),
        after("/hfr/Photonumerique/Galerie-Perso/liste_sujet-1.htm", link("Divers", "Photonumerique/Divers-7")),
        after("/hfr/WindowsSoftware/Windows-nt-2k-xp/liste_sujet-1.htm", link("Win 9x/Me", "WindowsSoftware/Win-9x-me")),
        after("/hfr/Programmation/C-2/liste_sujet-1.htm", link("C#/.NET managed", "Programmation/CNET-managed")),
        after("/hfr/Programmation/Delphi-Pascal/liste_sujet-1.htm", link("Flash/ActionScript", "Programmation/Flash-ActionScript")),
        after(
            "/hfr/Programmation/Java/liste_sujet-1.htm",
            link("Langages fonctionnels", "Programmation/Langages-fonctionnels"),
            link("PDA", "Programmation/PDA"),
            link("Perl", "Programmation/Perl")
        ),
        after(
            "/hfr/Programmation/PHP/liste_sujet-1.htm",
            link("Python", "Programmation/Python"),
            link("Ruby/Rails", "Programmation/Ruby")
        ),
        after("/hfr/Programmation/SGBD-SQL/liste_sujet-1.htm", link("Shell/Batch", "Programmation/Shell-Batch")),
        after("/hfr/Programmation/VB-VBA-VBS/liste_sujet-1.htm", link("XML/XSL", "Programmation/XML-XSL")),
        after(
            "/hfr/Graphisme/Arts-traditionnels/liste_sujet-1.htm",
            link("Concours", "Graphisme/Concours-2"),
            link("Ressources", "Graphisme/Ressources"),
            link("Divers", "Graphisme/Divers-5")
        ),
        after("/hfr/AchatsVentes/Softs-livres/liste_sujet-1.htm", link("Divers", "AchatsVentes/Divers-4")),
        after("/hfr/AchatsVentes/Feedback/liste_sujet-1.htm", link("Règles et coutumes", "AchatsVentes/Regles-coutumes"))
    ]

    /// An injection that only adds sub-forums after the trigger.
    private static func after(_ trigger: String, _ links: ForumLink...) -> SubforumInjection {
        SubforumInjection(trigger: trigger, before: [], after: links)
    }
}
