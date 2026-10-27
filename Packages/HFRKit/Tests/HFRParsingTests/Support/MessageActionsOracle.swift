import Foundation

/// The per-message action links of a LOT-003 topic oracle: `result.messages[]` (the raw `LinkItem` fields, read with
/// `ParseMessagesOperation.m:371-390`) and `result.actions[]` (the absolute URLs `ObjCMessageActionsBuilder` made of them).
struct MessageActionsOracle: Decodable {
    /// The raw link fields of a legacy `LinkItem`.
    struct Message: Decodable {
        var index: Int
        var postID: String?
        var urlQuote: String?
        var urlEdit: String?
        var urlAlert: String?
        var urlProfil: String?
        var privateMessageURL: String?
        var addFlagUrl: String?
        var quoteJS: String?

        enum CodingKeys: String, CodingKey {
            case index, postID, urlQuote, urlEdit, urlAlert, urlProfil, addFlagUrl, quoteJS
            case privateMessageURL = "MPUrl"
        }
    }

    /// One entry of `swiftMessageActionsByIndex`; absent keys are actions legacy did not offer.
    struct Actions: Decodable {
        var index: Int
        var quoteURL: String?
        var editURL: String?
        var alertURL: String?
        var profileURL: String?
        var privateMessageURL: String?
        var favoriteURL: String?
        var quoteJS: String?
    }

    struct Result: Decodable {
        var messages: [Message]
        var actions: [Actions]
    }

    var exception: String?
    var result: Result

    /// The oracle of a case id such as `R21`.
    static func load(_ caseID: String) throws -> MessageActionsOracle {
        let json = try Fixture.text("\(caseID).oracle", extension: "json", subdirectory: TopicOracle.subdirectory)
        return try JSONDecoder().decode(MessageActionsOracle.self, from: Data(json.utf8))
    }
}
