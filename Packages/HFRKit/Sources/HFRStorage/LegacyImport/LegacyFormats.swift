import Foundation
import HFRModels

/// The legacy app's keys and file names (`2fe43da3`), in one place.
public enum LegacyKeys {
    /// `SuperFavoritesIds` (`Favorites.swift:133`).
    public static let superFavorites = "SuperFavoritesIds"
    /// `CollapsedFavoriteSectionIDs` (`Favorites.swift:160`).
    public static let collapsedSections = "CollapsedFavoriteSectionIDs"
    /// `smileySearchHistory_v1` (`SmileySearchService.swift:89`).
    public static let smileySearchHistory = "smileySearchHistory_v1"
    /// `reply_active_drafts_by_topic_v1` (`AnswerView.swift:140`).
    public static let activeReplyDrafts = "reply_active_drafts_by_topic_v1"
    /// `brouillon`, the ObjC composer's single draft (`AddMessageViewController.m:69, 483`).
    public static let objcDraft = "brouillon"
    /// `blackListDico.plist` (`Constants.h:92`).
    public static let blocklistFile = "blackListDico.plist"
    /// `blackList.plist`, the v0 blocklist (`Constants.h:91`).
    public static let blocklistV0File = "blackList.plist"
    /// `whiteList.plist` (`Constants.h:93`).
    public static let allowlistFile = "whiteList.plist"
    /// `smiley_favorites_cache2` (`SmileyCache.m:18`).
    public static let smileyFavoritesFile = "smiley_favorites_cache2"
    /// `rehostImagesSwiftUI.json` (`ReplyService.swift:1936`).
    public static let uploadHistoryFile = "rehostImagesSwiftUI.json"
}

/// One legacy app smiley favourite (`SmileyFavorite`, `SmileyCache.m:26-40`).
struct LegacySmileyFavorite: Equatable {
    var code: String
    var url: String
    var addedAt: Date
}

/// One active draft of the legacy Swift composer (`ReplyDraftStore.ActiveDraftItem`, `AnswerView.swift:143-148`).
struct LegacyActiveDraft: Equatable {
    var topicNumber: Int
    var text: String
    var updatedAt: Date
}

/// Decoders of the legacy on-device formats. Pure functions: bytes or values in, values out. Each mirrors the legacy
/// loader, so what is imported is what the legacy app showed; nil means "the legacy app would have shown nothing".
enum LegacyFormats {
    /// Super-favourite topic numbers as `FavoritesSuperFavoriteStore.load()` read them (`Favorites.swift:135-150`):
    /// numbers, booleans and numeric strings, above 0, each once, sorted.
    static func superFavoriteNumbers(_ value: LegacyValue?) -> [Int] {
        guard case .array(let items) = value else { return [] }
        return Set(items.compactMap(\.legacyInteger).filter { $0 > 0 }).sorted()
    }

    /// Collapsed section ids as `FavoritesCollapsedSectionsStore.load()` read them (`Favorites.swift:162-170`): the
    /// array only when every element is a string (`as? [String]`), trimmed, empty ones dropped, each once.
    static func collapsedSections(_ value: LegacyValue?) -> [String] {
        guard case .array(let items) = value else { return [] }
        var texts: [String] = []
        for item in items {
            guard case .string(let text) = item else { return [] }
            texts.append(text)
        }
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Set(trimmed).sorted()
    }

    private struct SearchEntry: Decodable {
        let text: String
        let count: Int
        let lastDate: Date
    }

    /// The smiley search history (`SmileySearchService.swift:78-98`); nil when it does not decode (legacy's `try?`).
    static func searchHistory(_ value: LegacyValue?) -> [SmileySearchHistoryEntry]? {
        guard case .data(let data) = value,
              let entries = try? JSONDecoder().decode([SearchEntry].self, from: data) else { return nil }
        return entries.map { SmileySearchHistoryEntry(text: $0.text, count: $0.count, lastSearchedAt: $0.lastDate) }
    }

    private struct UploadedImage: Decodable {
        let fullWidth: Int?
        let fullHeight: Int?
        let fullURL: String
        let mediumURL: String?
        let miniURL: String?
        let timeStamp: Date
    }

    /// The upload history, newest first (`ReplyService.swift:1852-1870, 1938-1944`); nil when the file does not decode
    /// (legacy's `try?`). An entry whose full URL is not a URL is left out; `previewURL` has no counterpart (LOT-064).
    static func uploadHistory(_ data: Data) -> [RehostedImage]? {
        guard let images = try? JSONDecoder().decode([UploadedImage].self, from: data) else { return nil }
        return images.compactMap { image in
            guard let full = URL(string: image.fullURL) else { return nil }
            return RehostedImage(
                fullURL: full,
                mediumURL: image.mediumURL.flatMap(URL.init(string:)),
                miniURL: image.miniURL.flatMap(URL.init(string:)),
                width: image.fullWidth,
                height: image.fullHeight,
                uploadedAt: image.timeStamp
            )
        }
    }

    private struct ActiveDraft: Decodable {
        let topicID: String
        let text: String
        let updatedAt: Date
    }

    /// Active drafts of the Swift composer (`AnswerView.swift:259-262`); nil when the value does not decode. An id that
    /// is not `post-<number above 0>` (`MessagesView.swift:3254-3262`) or a blank text is left out.
    static func activeDrafts(_ value: LegacyValue?) -> [LegacyActiveDraft]? {
        guard case .data(let data) = value,
              let drafts = try? JSONDecoder().decode([ActiveDraft].self, from: data) else { return nil }
        return drafts.compactMap { draft in
            guard draft.topicID.hasPrefix("post-"), let number = Int(draft.topicID.dropFirst(5)), number > 0,
                  !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LegacyActiveDraft(topicNumber: number, text: draft.text, updatedAt: draft.updatedAt)
        }
    }

    /// The pseudos of a legacy list (`[{word, alias, mode}]`, `BlackList.m:43, 51`), in order; entries without a
    /// string `word` are left out. Nil when the value is not an array.
    static func pseudoList(_ value: LegacyValue?) -> [String]? {
        guard case .array(let items) = value else { return nil }
        return items.compactMap { item in
            guard case .dictionary(let entry) = item, case .string(let word) = entry["word"] else { return nil }
            return word
        }
    }

    /// `blackListDico.plist`: account name → list (`BlackList.m:91-103, 185`). Nil when not a dictionary.
    static func blocklists(_ value: LegacyValue?) -> [String: [String]]? {
        guard case .dictionary(let lists) = value else { return nil }
        return lists.compactMapValues { pseudoList($0) }
    }

    /// The app smiley favourites of a `smiley_favorites_cache2` archive, oldest first, equal dates in code order
    /// (`SmileyCache.m:350-380`; the dictionary has no order of its own). Nil when it is not such an archive.
    static func smileyFavorites(_ data: Data) -> [LegacySmileyFavorite]? {
        guard case .dictionary(let archive)? = try? BinaryPropertyList.parse(data),
              case .array(let objects)? = archive["$objects"],
              case .dictionary(let top)? = archive["$top"],
              let rootReference = top["$0"] ?? top["root"],
              case .dictionary(let root)? = KeyedArchive.resolve(rootReference, in: objects),
              case .array(let keys)? = root["NS.keys"], case .array(let values)? = root["NS.objects"],
              keys.count == values.count else { return nil }
        var favorites: [LegacySmileyFavorite] = []
        for value in values {
            guard case .dictionary(let favorite)? = KeyedArchive.resolve(value, in: objects),
                  let code = KeyedArchive.string(favorite["sCode"], in: objects),
                  let url = KeyedArchive.string(favorite["sRawUrl"], in: objects),
                  let date = KeyedArchive.date(favorite["dateAdded"], in: objects) else { return nil }
            favorites.append(LegacySmileyFavorite(code: code, url: url, addedAt: date))
        }
        return favorites.sorted { $0.addedAt == $1.addedAt ? $0.code < $1.code : $0.addedAt < $1.addedAt }
    }
}

/// Reading helpers for an `NSKeyedArchiver` object table, without instantiating any class.
enum KeyedArchive {
    /// The object a reference points to (one hop), or the node itself when it is not a reference.
    static func resolve(_ node: PlistNode?, in objects: [PlistNode]) -> PlistNode? {
        guard let node else { return nil }
        guard case .uid(let index) = node else { return node }
        guard objects.indices.contains(index) else { return nil }
        return objects[index]
    }

    /// An `NSString` (plain string) or `NSMutableString` (`{NS.string}`).
    static func string(_ node: PlistNode?, in objects: [PlistNode]) -> String? {
        switch resolve(node, in: objects) {
        case .string(let text): text
        case .dictionary(let object): object["NS.string"].flatMap { if case .string(let text) = $0 { text } else { nil } }
        default: nil
        }
    }

    /// An `NSDate` (`{NS.time}`, seconds since 2001).
    static func date(_ node: PlistNode?, in objects: [PlistNode]) -> Date? {
        guard case .dictionary(let object)? = resolve(node, in: objects) else { return nil }
        switch object["NS.time"] {
        case .real(let time)?: return Date(timeIntervalSinceReferenceDate: time)
        case .integer(let time)?: return Date(timeIntervalSinceReferenceDate: TimeInterval(time))
        default: return nil
        }
    }
}
