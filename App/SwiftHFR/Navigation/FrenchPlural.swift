/// French plural rule: zero and one are singular.
enum FrenchPlural {
    /// "1 réponse", "0 réponse", "2 réponses".
    static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(abs(number) <= 1 ? singular : plural)"
    }
}
