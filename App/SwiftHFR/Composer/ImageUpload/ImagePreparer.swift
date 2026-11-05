import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why a picked image could not be turned into the JPEG that is uploaded.
enum ImagePreparationError: Error, Equatable, Sendable {
    /// The bytes are not an image the system can decode.
    case unreadable
    /// Encoding the JPEG failed.
    case encodingFailed
}

/// Turns a picked image into the JPEG sent to the host.
protocol ImagePreparing: Sendable {
    /// JPEG bytes of `source`, upright, no longer than `maxDimension` pixels on its longest side, with no metadata.
    func prepare(_ source: Data, maxDimension: Int) throws(ImagePreparationError) -> Data
}

// Port of HFRswift/Swift/ReplyService.swift (UIImage.rehostPreparedForUpload, Img3ReplyImageUploadService.uploadImage) @ 2440d79.
// Differences: ImageIO instead of a UIKit redraw, so the output carries no EXIF/GPS block (LOT-071 T4, #193 privacy note); the
// source is the picked file's bytes, not a decoded `UIImage`.
/// Downscales (never upscales), applies the orientation and re-encodes at quality 1.0 (legacy `jpegData(compressionQuality: 1.0)`,
/// `ReplyService.swift:1984`).
///
/// A re-encode through `CGImageDestination` writes only the properties it is given: none besides the quality, so neither the
/// camera's EXIF nor a GPS block survives (checked on the output bytes by the tests, measured on a device by the Mac check).
struct ImageIOPreparer: ImagePreparing {
    func prepare(_ source: Data, maxDimension: Int) throws(ImagePreparationError) -> Data {
        guard let reader = CGImageSourceCreateWithData(source as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(reader, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw .unreadable }
        // The thumbnail call scales up when asked for more than the image has: cap at the real size.
        let target = min(max(maxDimension, 1), max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(reader, 0, options as CFDictionary) else { throw .unreadable }
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .encodingFailed
        }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(writer), output.length > 0 else { throw .encodingFailed }
        return output as Data
    }
}
