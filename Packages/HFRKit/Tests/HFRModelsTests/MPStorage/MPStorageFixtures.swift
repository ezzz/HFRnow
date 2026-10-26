import Foundation
@testable import HFRModels

/// Synthetic documents and helpers shared by the MPStorage mutation, merge and codec tests.
enum MPStorageFixtures {
    /// Shape of a real document (audit E23): other clients' namespaces, writer metadata at every level.
    static let wild = """
    {"data":[{"version":"0.1",
      "mpFlags":{"list":[{"post":123,"p":"1","href":"/h","page":4,"uri":"/u"}],"active":true},
      "blacklist":{"list":[{"createDate":1700000000000,"username":"Troll"}]},
      "bookmarks":{"list":[
        {"createDate":1700000000123,"post":"1711","author":"Bob","numreponse":55,"cat":"13","label":"L","color":"red"}],
        "sourceName":"iOS","lastUpdate":1700000000500},
      "hfrChat":{"x":[1,2,{"y":null}]},"superFavs":{},"sourceName":"DTCloud_GM","lastUpdate":1700000001000}],
     "sourceName":"DTCloud_GM","lastUpdate":1700000001000,"futureRootKey":"keep me"}
    """

    static func document(_ text: String = wild) throws -> MPStorageDocument {
        try MPStorageCodec.decode(text)
    }

    static func stamp(_ seconds: TimeInterval, _ source: String = "SwiftHFR") -> MPStorageStamp {
        MPStorageStamp(sourceName: source, date: Date(timeIntervalSince1970: seconds))
    }

    /// A stamp with the tombstone write policy on.
    static func recording(_ seconds: TimeInterval) -> MPStorageStamp {
        MPStorageStamp(sourceName: "SwiftHFR", date: Date(timeIntervalSince1970: seconds), recordsTombstones: true)
    }

    static func bookmark(_ numreponse: Int, label: String = "", created: TimeInterval? = 1_700_000_000) -> MPStorageBookmark {
        MPStorageBookmark(
            topic: 1711, category: "13", numreponse: numreponse, author: "Bob", label: label,
            createdAt: created.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

extension MPStorageDocument {
    /// The `0.1` entry, for assertions.
    var primary: MPStorageEntry {
        get { data[writableEntryIndex ?? 0] }
        set { data[writableEntryIndex ?? 0] = newValue }
    }
}

extension JSONValue {
    /// The member of an object, for assertions.
    func member(_ key: String) -> JSONValue? {
        guard case let .object(members) = self else { return nil }
        return members[key]
    }
}
