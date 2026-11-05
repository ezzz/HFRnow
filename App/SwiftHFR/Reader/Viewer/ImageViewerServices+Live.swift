import HFRNetwork
import ImageIO
import Photos
import UIKit

extension ImageViewerServices {
    /// The real services: downloads through `fetcher` with the host table's `Referer` rules (cookie-less, never the account
    /// session), saves with the add-only Photos permission (legacy `MessageImagePhotoLibrarySaver`), copies to the pasteboard.
    static func live(fetcher: ReaderImageFetcher) -> ImageViewerServices {
        ImageViewerServices(
            load: { url, allowsThirdParty in
                let result = try await fetcher.image(at: url, allowsThirdParty: allowsThirdParty, hostTable: .standard)
                // Decoded in the app, not in WebKit's process: refuse what cannot be shown or would blow the memory.
                // The same bounded decode the viewer does, here and off the main actor: a truncated image never becomes `.loaded`.
                guard ViewerImageCheck.isShowable(result.data), ViewerImageCheck.displayImage(result.data) != nil else {
                    throw ImageSaveError.invalidImage
                }
                return ViewerImage(data: result.data, mimeType: result.mimeType)
            },
            save: { image async throws(ImageSaveError) in try await PhotoLibrarySaver.save(image.data) },
            copy: { UIPasteboard.general.string = $0.absoluteString }
        )
    }
}

/// What the viewer accepts to decode: bytes that name an image type, hold an image and stay under a pixel budget.
enum ViewerImageCheck {
    /// Most pixels an image may hold: a few megabytes of PNG can claim billions.
    static let maximumPixels = 100_000_000
    /// Longest side of the bitmap the viewer builds: the source is sampled down to it, never decoded at full size.
    static let displayMaximumSide = 4096

    /// True when `data` is a decodable image within the pixel budget.
    static func isShowable(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return false }
        return width <= maximumPixels / height
    }

    /// The image sampled down to `displayMaximumSide`, never decoded at full size.
    static func displayImage(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: displayMaximumSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// Writes image bytes to the photo library, asking for add-only access the first time (legacy `MessagesView.swift:2430-2490`).
enum PhotoLibrarySaver {
    static func save(_ data: Data) async throws(ImageSaveError) {
        guard ViewerImageCheck.isShowable(data) else { throw .invalidImage }
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        guard status == .authorized || status == .limited else { throw .permissionDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw .system
        }
    }
}
