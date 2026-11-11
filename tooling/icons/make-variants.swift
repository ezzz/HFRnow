// Derives the Dark and Tinted layers of a full-art icon from its Default 1024 px PNG (macOS, CoreImage).
// Usage: swift tooling/icons/make-variants.swift App/SwiftHFR/Icon-NOEL-HFR.icon/Assets/Icon-NOEL-HFR_1024.png
// Dark: same drawing, exposure lowered so it sits well on a dark Home Screen. Tinted: greyscale, which the system tints.
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2, let input = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write(Data("ko   usage: make-variants.swift <Icon-X_1024.png>\n".utf8))
    exit(1)
}
let base = CommandLine.arguments[1].replacingOccurrences(of: ".png", with: "")
let context = CIContext()

func write(_ image: CIImage, _ path: String) {
    guard let cg = context.createCGImage(image, from: input.extent),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("ko   cannot write \(path)\n".utf8)); exit(1)
    }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { exit(1) }
    print("ok   \(path)")
}

let dark = input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.3, kCIInputSaturationKey: 0.9])
let tinted = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.1])
write(dark, base + "_dark.png")
write(tinted, base + "_tinted.png")
