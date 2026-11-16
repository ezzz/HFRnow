// Derives the app's Noël soft images (LOT-166) from the operator's validated renders in docs/assets/themes/renders/
// (2026-11-10): trims the transparent margin, scales so the longest side is at most the given size, writes a transparent PNG.
// No pixel is drawn here. Usage, from the repository root (macOS):
//   swift tooling/art/noel-crossings/derive.swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Render name, imageset name, longest side in pixels (3x of the largest size drawn).
let jobs: [(String, String, Int)] = [
    ("noel_sleigh", "NoelSleigh", 900), // up to 240 pt high: the render's full size, upscaled on screen
    ("noel_star", "NoelStar", 256), // 64 pt
    ("noel_gift", "NoelGift", 256),
    ("noel_gift_blue", "NoelGiftBlue", 256),
    ("noel_gift_gold", "NoelGiftGold", 256),
    ("noel_ornament", "NoelOrnament", 256),
    ("noel_snowflake", "NoelSnowflake", 256),
    ("noel_snowpile", "NoelSnowPile", 660) // the bottom drifts: up to 220 pt wide
]

func trimmedBounds(_ image: CGImage) -> CGRect {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = -1, maxY = -1
    for row in 0..<height {
        for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 8 {
            minX = min(minX, column); maxX = max(maxX, column); minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    // Rows of the bitmap context run bottom-up from CGImage's top-down rows: flip back.
    return CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for (render, set, longest) in jobs {
    let source = root.appendingPathComponent("docs/assets/themes/renders/\(render).png")
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { fatalError("cannot read \(source.path)") }
    let bounds = trimmedBounds(image)
    guard let cropped = image.cropping(to: bounds) else { fatalError("cannot crop \(render)") }
    let scale = min(1, Double(longest) / Double(max(cropped.width, cropped.height)))
    let width = Int((Double(cropped.width) * scale).rounded()), height = Int((Double(cropped.height) * scale).rounded())
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    let folder = root.appendingPathComponent("App/SwiftHFR/Assets.xcassets/Noel/\(set).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("\(render).png")
    guard let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(file.path)")
    }
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("cannot write \(file.path)") }
    let contents = """
    {
      "images" : [
        {
          "filename" : "\(render).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("\(set): \(bounds.width)x\(bounds.height) -> \(width)x\(height)")
}
