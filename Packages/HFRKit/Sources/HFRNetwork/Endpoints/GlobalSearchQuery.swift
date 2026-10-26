import HFRModels

/// Parameters of the global search form (HFR-PROTOCOL S1), ported from `ForumSearchParams` (`ForumSearchService.swift:10-127`).
public struct GlobalSearchQuery: Sendable, Equatable {
    /// Which words must match (`searchtype`).
    public enum MatchMode: String, Sendable, CaseIterable {
        /// Every word (`searchtype=1`, the default).
        case allWords = "1"
        /// At least one word (`searchtype=2`).
        case anyWord = "2"
        /// Advanced query syntax (`searchtype=0`).
        case advanced = "0"
    }

    /// Where the words are looked for (`titre`).
    public enum Scope: String, Sendable, CaseIterable {
        /// Title and content (`titre=3`, the default).
        case titleAndContent = "3"
        /// Title only (`titre=1`).
        case title = "1"
        /// Content only (`titre=0`).
        case content = "0"
    }

    /// How far back the search goes (`daterange`, plus `jour`/`mois`/`annee` for a start date).
    public enum DateRange: Sendable, Equatable {
        /// From the beginning of the forum (`daterange=2`, no date fields).
        case fromBeginning
        /// From a given day (`daterange=1`, then `jour`, `mois`, `annee`). The caller computes the date, keeping the builder pure.
        case since(day: Int, month: Int, year: Int)
    }

    /// Words to search; lowercased in the body, as legacy did (`ObjCForumSearchWorker.m:149`).
    public var text: String
    /// Forum to search in; legacy default is 13 (Discussions).
    public var category: CategoryID
    /// Word matching mode.
    public var matchMode: MatchMode
    /// Fields searched.
    public var scope: Scope
    /// Date restriction.
    public var dateRange: DateRange

    /// Creates a query with the legacy defaults (`cat=13`, all words, title and content, from the beginning).
    public init(
        text: String,
        category: CategoryID = .forum(13),
        matchMode: MatchMode = .allWords,
        scope: Scope = .titleAndContent,
        dateRange: DateRange = .fromBeginning
    ) {
        self.text = text
        self.category = category
        self.matchMode = matchMode
        self.scope = scope
        self.dateRange = dateRange
    }
}
