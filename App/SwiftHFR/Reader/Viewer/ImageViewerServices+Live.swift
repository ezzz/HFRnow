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
                return ViewerImage(data: result.data, mimeType: result.mimeType)
            },
            save: { image async throws(ImageSaveError) in try await PhotoLibrarySaver.save(image.data) },
            copy: { UIPasteboard.general.url = $0 }
        )
    }
}

/// Writes image bytes to the photo library, asking for add-only access the first time (legacy `MessagesView.swift:2430-2490`).
enum PhotoLibrarySaver {
    static func save(_ data: Data) async throws(ImageSaveError) {
        // A source exists for almost any bytes: it must name an image type and hold at least one image (an SVG does not).
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0 else { throw .invalidImage }
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
