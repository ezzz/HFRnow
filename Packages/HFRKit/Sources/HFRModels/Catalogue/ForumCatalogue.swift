/// Static knowledge of HFR forums: which `cat` id each forum path maps to.
///
/// The home page does not link `cat` ids, so the table is the only source (legacy `Forum.m:34-60`).
/// Lookups match paths exactly, as the legacy `isEqualToString:` comparisons did.
public enum ForumCatalogue {
    /// Every known forum path, in legacy order. `ia` appears twice: relative and absolute (legacy `Forum.m:57-58`).
    public static let entries: [ForumCatalogueEntry] = [
        ForumCatalogueEntry(path: "/hfr/Hardware/liste_sujet-1.htm", categoryID: .forum(1)),
        ForumCatalogueEntry(path: "/hfr/HardwarePeripheriques/liste_sujet-1.htm", categoryID: .forum(16)),
        ForumCatalogueEntry(path: "/hfr/OrdinateursPortables/liste_sujet-1.htm", categoryID: .forum(15)),
        ForumCatalogueEntry(path: "/hfr/gsmgpspda/liste_sujet-1.htm", categoryID: .forum(23)),
        ForumCatalogueEntry(path: "/hfr/OverclockingCoolingModding/liste_sujet-1.htm", categoryID: .forum(2)),
        ForumCatalogueEntry(path: "/hfr/electroniquedomotiquediy/liste_sujet-1.htm", categoryID: .forum(30)),
        ForumCatalogueEntry(path: "/hfr/apple/liste_sujet-1.htm", categoryID: .forum(25)),
        ForumCatalogueEntry(path: "/hfr/VideoSon/liste_sujet-1.htm", categoryID: .forum(3)),
        ForumCatalogueEntry(path: "/hfr/Photonumerique/liste_sujet-1.htm", categoryID: .forum(14)),
        ForumCatalogueEntry(path: "/hfr/JeuxVideo/liste_sujet-1.htm", categoryID: .forum(5)),
        ForumCatalogueEntry(path: "/hfr/WindowsSoftware/liste_sujet-1.htm", categoryID: .forum(4)),
        ForumCatalogueEntry(path: "/hfr/reseauxpersosoho/liste_sujet-1.htm", categoryID: .forum(22)),
        ForumCatalogueEntry(path: "/hfr/systemereseauxpro/liste_sujet-1.htm", categoryID: .forum(21)),
        ForumCatalogueEntry(path: "/hfr/OSAlternatifs/liste_sujet-1.htm", categoryID: .forum(11)),
        ForumCatalogueEntry(path: "/hfr/Programmation/liste_sujet-1.htm", categoryID: .forum(10)),
        ForumCatalogueEntry(path: "/hfr/Graphisme/liste_sujet-1.htm", categoryID: .forum(12)),
        ForumCatalogueEntry(path: "/hfr/AchatsVentes/liste_sujet-1.htm", categoryID: .forum(6)),
        ForumCatalogueEntry(path: "/hfr/EmploiEtudes/liste_sujet-1.htm", categoryID: .forum(8)),
        ForumCatalogueEntry(path: "/hfr/Setietprojetsdistribues/liste_sujet-1.htm", categoryID: .forum(9)),
        ForumCatalogueEntry(path: "/hfr/Discussions/liste_sujet-1.htm", categoryID: .forum(13)),
        ForumCatalogueEntry(path: "/hfr/Blabla-Divers-back-to-life/liste_sujet-1.htm", categoryID: .forum(24)),
        ForumCatalogueEntry(path: "/hfr/ia/liste_sujet-1.htm", categoryID: .forum(32)),
        ForumCatalogueEntry(path: "https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm", categoryID: .forum(32))
    ]

    /// Path to category, exact match; nil for a path the table does not know.
    public static func categoryID(forPath path: String) -> CategoryID? {
        entries.first { $0.path == path }?.categoryID
    }

    /// Canonical relative path of a category: the first row that carries it, which is never an absolute alias.
    public static func forumPath(for categoryID: CategoryID) -> String? {
        entries.first { $0.categoryID == categoryID }?.path
    }
}
