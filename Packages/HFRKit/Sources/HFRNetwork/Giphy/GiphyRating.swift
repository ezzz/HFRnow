/// The `rating` request parameter: a ceiling, not a filter (the captured `rating=r` answers all carried `g`).
public enum GiphyRating: String, Sendable, Equatable, CaseIterable {
    /// `g`.
    case general = "g"
    /// `pg`.
    case parentalGuidance = "pg"
    /// `pg-13`.
    case parentalGuidance13 = "pg-13"
    /// `r`, the rating legacy asked for (`AnswerView.swift:2305` @ 2440d79).
    case restricted = "r"
}
