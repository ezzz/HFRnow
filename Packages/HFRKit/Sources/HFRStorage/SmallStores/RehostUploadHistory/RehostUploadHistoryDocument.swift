import HFRModels

/// What the upload history persists: device-only, global, personal data that never leaves the device (ADR 0013 §1).
public struct RehostUploadHistoryDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// An empty history.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// The uploaded images, the last one added first.
    public var images: [RehostedImage]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, images: [RehostedImage] = []) {
        self.version = version
        self.images = images
    }
}
