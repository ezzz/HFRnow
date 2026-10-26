/// Failures of the cache helpers.
public enum CacheError: Error, Sendable, Equatable {
    /// The key is empty once normalised.
    case emptyKey
    /// The key is longer than `AvatarCache.maximumKeyBytes`.
    case keyTooLong
    /// Empty data is never cached (it would replace a valid file with nothing).
    case emptyData
    /// A file name prefix or extension is empty, too long, or has characters other than letters, digits, `-` and `_`.
    case invalidFileName
    /// The cache root or an area folder is a symbolic link, or resolves outside the cache root: nothing is read or written there.
    case unsafeFolder
}
