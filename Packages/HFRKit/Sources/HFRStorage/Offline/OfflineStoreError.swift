/// Why the offline store refused or failed. No case carries page content.
public enum OfflineStoreError: Error, Sendable, Equatable {
    /// Only forum topics with a positive number, and pages from 1 on, are saved.
    case invalidTopic
    /// An empty page is never saved (it would replace a readable one with nothing).
    case emptyPage
    /// The page holds a non-empty `hash_check`: it was fetched with the account's session, and the token must not be
    /// written to disk. Offline pages are fetched without cookies (HFR-PROTOCOL §7 E25).
    case containsSessionToken
    /// The topic already holds `maximumPagesPerTopic` pages, all after this one.
    case beyondPageLimit
    /// The page file was written by a format this build does not read (`OfflineTopicStore.currentVersion`).
    case unsupportedVersion(Int)
    /// The page file exists but cannot be read (truncated, not JSON, wrong fields).
    case unreadable
    /// The cache folder is a symbolic link or resolves outside the cache (LOT-066).
    case unsafeFolder
    /// Writing or removing a file failed; `reason` is the system's message.
    case fileFailed(reason: String)
}
