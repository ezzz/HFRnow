import HFRModels

/// The order the small stores save topics in: forum categories by number, private messages last, then topic number.
enum TopicOrder {
    /// Whether `lhs` comes before `rhs`.
    static func precedes(_ lhs: TopicID, _ rhs: TopicID) -> Bool {
        let left = rank(of: lhs.category)
        let right = rank(of: rhs.category)
        return left == right ? lhs.topic < rhs.topic : left < right
    }

    private static func rank(of category: CategoryID) -> (Int, Int) {
        switch category {
        case .forum(let number): (0, number)
        case .privateMessages: (1, 0)
        }
    }
}
