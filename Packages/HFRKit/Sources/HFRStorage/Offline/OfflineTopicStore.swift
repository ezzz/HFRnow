import Foundation
import HFRModels

/// Topic pages saved for reading without network (LOT-068, audit E-8, decision Q-5), in the `offline` area of the
/// LOT-066 cache: device-only, never backed up, and reclaimable by the system like any cache (ADR 0013).
///
/// Each page is one self-contained file, `offline/<category>-<topic>/<page>.json`, holding the page's HTML as HFR served
/// it to a visitor, its title and the save date. There is no index to keep in step: the list is read from the files, so
/// the LOT-066 evictor (200 MB, pages saved longest ago first) or the system can remove any page without breaking the
/// others. The store is shared by every account on the device: the pages carry no session (`containsSessionToken`), so
/// they are the same for all of them. Fetching the pages is the app's job (LOT-139); the parser reads them back.
public struct OfflineTopicStore: Sendable {
    /// The page file format this build writes and reads.
    public static let currentVersion = 1
    /// Pages kept per topic: 50 pages is 2,000 messages, at most a few megabytes per topic. Legacy had no offline reading
    /// in use (its download method is commented out, `OfflineStorage.m:145-294`), so no limit to keep.
    public static let defaultMaximumPagesPerTopic = 50

    /// The cache holding the `offline` area.
    public let cache: CacheDirectory
    /// Pages kept per topic: saving one more removes the topic's lowest-numbered pages.
    public let maximumPagesPerTopic: Int

    /// Creates the store over `cache` (tests pass a temporary one).
    public init(cache: CacheDirectory = .standard, maximumPagesPerTopic: Int = defaultMaximumPagesPerTopic) {
        self.cache = cache
        self.maximumPagesPerTopic = max(1, maximumPagesPerTopic)
    }

    // MARK: - Writing

    /// Saves `page`, replacing the file of the same page (the topic's last page grows: the app saves it again).
    ///
    /// Beyond `maximumPagesPerTopic`, the topic's lowest-numbered pages are removed; a page lower than every one of a
    /// full topic is refused (`beyondPageLimit`), since it would be the one removed.
    /// - Throws: `invalidTopic`, `emptyPage`, `containsSessionToken`, `beyondPageLimit` before writing; `unsafeFolder`,
    ///   `fileFailed`.
    public func save(_ page: OfflinePage) throws(OfflineStoreError) {
        let folder = try topicFolder(page.topic)
        guard page.page >= 1 else { throw .invalidTopic }
        guard !page.html.isEmpty else { throw .emptyPage }
        guard !OfflinePageRecord.holdsSessionToken(page.html) else { throw .containsSessionToken }
        var saved = pageNumbers(in: folder).filter { $0 != page.page }
        if saved.count >= maximumPagesPerTopic, let lowest = saved.min(), page.page < lowest { throw .beyondPageLimit }
        let data: Data
        do {
            data = try OfflinePageRecord.encode(OfflinePageRecord(page))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: Self.file(page.page, in: folder), options: .atomic)
        } catch {
            throw .fileFailed(reason: error.localizedDescription)
        }
        saved.sort()
        while saved.count >= maximumPagesPerTopic {
            try remove(Self.file(saved.removeFirst(), in: folder))
        }
    }

    /// Removes every saved page of `topic`.
    public func remove(_ topic: TopicID) throws(OfflineStoreError) {
        let folder = try topicFolder(topic)
        for number in pageNumbers(in: folder) { try remove(Self.file(number, in: folder)) }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes every saved page (LOT-066's `clear`, which keeps the area's folder).
    public func removeAll() throws(OfflineStoreError) {
        let report = cache.clear(.offlineTopics)
        if let failure = report.failures.first { throw .fileFailed(reason: failure) }
    }

    // MARK: - Reading

    /// The topics with saved pages, most recently saved first. Topic folders without a page file are left out.
    public func topics() throws(OfflineStoreError) -> [OfflineTopic] {
        let area = try areaURL()
        let folders = (try? FileManager.default.contentsOfDirectory(at: area, includingPropertiesForKeys: nil)) ?? []
        let topics = folders.compactMap { folder -> OfflineTopic? in
            guard !Self.isSymbolicLink(folder), let topic = Self.topicID(folderName: folder.lastPathComponent) else { return nil }
            let numbers = pageNumbers(in: folder)
            guard !numbers.isEmpty else { return nil }
            let title = numbers.reversed().lazy.compactMap { try? self.read(Self.file($0, in: folder))?.title }.first ?? ""
            let dates = numbers.compactMap { Self.modificationDate(Self.file($0, in: folder)) }
            return OfflineTopic(topic: topic, title: title, pages: numbers, lastSavedAt: dates.max() ?? .distantPast)
        }
        return topics.sorted { ($0.lastSavedAt, $1.topic.topic) > ($1.lastSavedAt, $0.topic.topic) }
    }

    /// The saved page `number` of `topic`; nil when it was never saved or has been evicted.
    /// - Throws: `unsupportedVersion` for a file of another format version, `unreadable` for a damaged one.
    public func page(_ number: Int, of topic: TopicID) throws(OfflineStoreError) -> OfflinePage? {
        guard number >= 1 else { throw .invalidTopic }
        let page = try read(Self.file(number, in: try topicFolder(topic)))
        // A file renamed by hand into another topic's folder or page number is not that page.
        guard page == nil || (page?.topic == topic && page?.page == number) else { throw .unreadable }
        return page
    }

    // MARK: - Files

    private func areaURL() throws(OfflineStoreError) -> URL {
        do {
            return try cache.safeURL(for: .offlineTopics)
        } catch {
            throw .unsafeFolder
        }
    }

    /// The folder of a forum topic, `<category>-<topic>`; a private conversation is never saved.
    private func topicFolder(_ topic: TopicID) throws(OfflineStoreError) -> URL {
        guard case .forum(let category) = topic.category, category > 0, topic.topic > 0 else { throw .invalidTopic }
        let folder = try areaURL().appending(path: "\(category)-\(topic.topic)", directoryHint: .isDirectory)
        guard !Self.isSymbolicLink(folder) else { throw .unsafeFolder }
        return folder
    }

    private func read(_ file: URL) throws(OfflineStoreError) -> OfflinePage? {
        guard !Self.isSymbolicLink(file) else { throw .unsafeFolder }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try OfflinePageRecord.decode(data)
    }

    private func remove(_ file: URL) throws(OfflineStoreError) {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) || Self.isSymbolicLink(file) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw .fileFailed(reason: error.localizedDescription)
        }
    }

    /// The page numbers of the regular `<n>.json` files of a topic folder, ascending.
    private func pageNumbers(in folder: URL) -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", !Self.isSymbolicLink(file), Self.isRegularFile(file) else { return nil }
            return Self.positiveNumber(file.deletingPathExtension().lastPathComponent)
        }.sorted()
    }

    private static func file(_ number: Int, in folder: URL) -> URL {
        folder.appending(path: "\(number).json", directoryHint: .notDirectory)
    }

    private static func topicID(folderName: String) -> TopicID? {
        let parts = folderName.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let category = positiveNumber(parts[0]), let topic = positiveNumber(parts[1]) else { return nil }
        return TopicID(category: .forum(category), topic: topic)
    }

    /// Decimal digits only, no sign, no leading zero, so one number has one file name.
    private static func positiveNumber(_ text: some StringProtocol) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), text.first != "0" else { return nil }
        return Int(text)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
