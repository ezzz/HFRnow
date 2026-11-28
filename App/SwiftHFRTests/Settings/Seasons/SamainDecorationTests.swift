import CoreGraphics
import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// The Samain themes as the engine draws them (LOT-191, THEMES.md §2, §3, §4 rules 6–7): two theme files of the « Samain » family,
/// their art behind the content, and the witch of the packing.
@MainActor
struct SamainDecorationTests {
    private func theme(_ seasonal: SeasonalTheme) throws -> ThemeDefinition {
        try #require(ThemeCatalog.bundled.themes.first { $0.id == seasonal.rawValue })
    }

    // MARK: Theme files

    @Test func theFilesAreBundledInTheSamainFamilyAndNeverInTheGallery() throws {
        let soft = try theme(.spooktoberSoft)
        #expect(soft.name == "Spooktober soft" && soft.family == "Samain" && soft.fontDesign == .default)
        #expect(soft.decorations == SamainLayout.Kind.soft.rawValue)
        guard case .lightDark? = soft.variants else {
            Issue.record("Spooktober soft has a light and a dark variant")
            return
        }
        let abuse = try theme(.spooktoberAbuse)
        #expect(abuse.name == "Spooktober abusé" && abuse.family == "Samain" && abuse.fontDesign == .rounded)
        #expect(abuse.decorations == SamainLayout.Kind.full.rawValue)
        guard case .single? = abuse.variants else {
            Issue.record("Spooktober abusé is « clair = sombre »")
            return
        }
        #expect(!ThemeCatalog.bundled.galleryFamilies.contains { $0.family == "Samain" })
    }

    /// Over Legacy or a gallery theme the tokens, the font and the art of the Spooktober theme replace the user's, which stays
    /// stored; the soft one follows the Clair / Sombre picker, the abusé one is dark whatever it says.
    @Test(arguments: [SeasonalTheme.spooktoberSoft, .spooktoberAbuse])
    func theirTokensFontAndArtReplaceTheUsersTheme(seasonal: SeasonalTheme) throws {
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store)
        model.mode = .light
        let stored = store.value(for: SettingKey.themeID)
        let drawn = model.appearance(drawing: seasonal)
        let definition = try theme(seasonal)
        #expect(drawn.themeVariants == definition.variants)
        #expect(drawn.themeDecorations == definition.decorations)
        #expect(drawn.themeFontDesign == definition.fontDesign)
        #expect(store.value(for: SettingKey.themeID) == stored)
        #expect(model.appearance(drawing: nil) == model.appearance)
        let scheme = model.colorScheme(drawing: drawn)
        #expect(scheme == (seasonal == .spooktoberAbuse ? .dark : .light))
    }

    /// A build without the file draws the user's theme unchanged rather than a half theme.
    @Test func withoutItsFileTheUsersThemeIsDrawn() throws {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        for seasonal in [SeasonalTheme.spooktoberSoft, .spooktoberAbuse] {
            #expect(model.appearance.applying(seasonal, catalog: catalog) == model.appearance)
        }
    }

    // MARK: Art

    @Test(arguments: SamainLayout.Art.allCases)
    func everyPieceOfArtHasItsTransparentImage(art: SamainLayout.Art) throws {
        let image = try #require(UIImage(named: art.rawValue))
        #expect(abs(image.size.width / image.size.height - art.aspectRatio) < 0.02)
        let alpha = image.cgImage?.alphaInfo
        #expect(alpha != CGImageAlphaInfo.none && alpha != .noneSkipLast && alpha != .noneSkipFirst)
    }

    /// Every image of Samain's art: the backdrop's, the crossings' and the packing witch's (a literal list so the argument of the
    /// test below needs no actor; `everyListedImageIsAnAssetOfTheArt` ties it to the types).
    nonisolated private static let everyImage = [
        "SamainWeb", "SamainCandelabra", "SamainBat", "SamainMoon", "SamainPumpkin", "SamainPumpkinPlain",
        "SamainWitch", "SamainGhost", "SamainVampire", "SamainLightning", "SamainWitchSweep"
    ]

    @Test func everyListedImageIsAnAssetOfTheArt() {
        let typed = Set(SamainLayout.Art.allCases.map(\.rawValue) + NoelCrossingItem.allCases.filter(\.isSamain).map(\.assetName))
        #expect(typed.union(["SamainWitchSweep"]) == Set(Self.everyImage))
    }

    /// The visible pixels of `name` that touch transparency (its silhouette), as colours.
    private func edgeColours(of name: String) throws -> [ThemeRGB] {
        let image = try #require(UIImage(named: name)?.cgImage)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func alpha(_ column: Int, _ row: Int) -> UInt8 {
            guard column >= 0, row >= 0, column < width, row < height else { return 0 }
            return pixels[(row * width + column) * 4 + 3]
        }
        var edges: [ThemeRGB] = []
        for row in 0..<height {
            for column in 0..<width where alpha(column, row) > 8 {
                let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { alpha(column + $0.0, row + $0.1) <= 8 }
                guard touches else { continue }
                let index = (row * width + column) * 4
                // The context holds premultiplied colours: undo it, so a faint edge pixel keeps the colour it was drawn in.
                let opacity = Int(pixels[index + 3])
                edges.append(ThemeRGB(
                    red: Int(pixels[index]) * 255 / opacity, green: Int(pixels[index + 1]) * 255 / opacity,
                    blue: Int(pixels[index + 2]) * 255 / opacity
                ))
            }
        }
        return edges
    }

    /// WCAG 1.4.11 (the lot's acceptance criterion, rule 7): every decoration on the soft theme's dark variant keeps its
    /// silhouette ≥ 3:1. The purple witch and vampire do not against the background (2.3:1), so on a dark scheme the art gets a
    /// light rim (`SamainRim`): every edge pixel of every image reads ≥ 3:1 against the background or against the rim, whose colour
    /// is the background under the halo's opacity of white.
    @Test(arguments: SamainDecorationTests.everyImage)
    func everyImageKeepsItsSilhouetteThreeToOneOnTheDarkBackgroundWithItsRim(name: String) throws {
        let background = try #require(try theme(.spooktoberSoft).variants?.dark.background)
        let rim = background.mixed(with: ThemeRGB(red: 255, green: 255, blue: 255), amount: SamainRim.opacity)
        #expect(rim.contrast(with: background) >= 3, "the rim \(rim) on \(background)")
        let edges = try edgeColours(of: name)
        try #require(!edges.isEmpty)
        let readable = edges.filter { $0.contrast(with: background) >= 3 || $0.contrast(with: rim) >= 3 }
        #expect(Double(readable.count) / Double(edges.count) >= 0.99, "\(name): \(readable.count) of \(edges.count) edge pixels")
    }

    /// The rim is real: the dark-scheme halo exists and the light scheme has none. (The witch's own purple, 2.3:1 on the
    /// background, is why: the test above fails without it.)
    @Test func theRimIsAWhiteHaloOnTheDarkSchemeOnly() {
        #expect(SamainRim.opacity >= 0.5 && SamainRim.radius >= 1)
    }

    /// The soft bat is drawn in the operator's colour for the scheme: ≥ 3:1 on the dark background (7.13:1 in the draft) and on
    /// the light one.
    @Test func theSoftBatIsDrawnInTheDraftsColourOnBothVariants() throws {
        let variants = try #require(try theme(.spooktoberSoft).variants)
        let light = variants.light
        let dark = variants.dark
        #expect(SamainLayout.batOnDark.contrast(with: dark.background) >= 7)
        #expect(SamainLayout.batOnLight.contrast(with: light.background) >= 3)
        #expect(SamainLayout.Kind.soft.opacity == 1)
    }

    /// The abusé art is drawn at `fullOpacity`: even a white pixel there keeps the text native screens draw on the background
    /// ≥ 4.5:1: the system label and its secondary label (60 % of #EBEBF5, the section headers) of the dark appearance the
    /// theme imposes, and the tint.
    @Test func theAbuseArtKeepsTheTextOnTheBackgroundReadable() throws {
        guard case let .single(tokens)? = try theme(.spooktoberAbuse).variants else {
            Issue.record("Spooktober abusé is single-variant")
            return
        }
        let white = ThemeRGB(red: 255, green: 255, blue: 255)
        let underArt = tokens.background.mixed(with: white, amount: SamainLayout.Kind.full.opacity)
        let secondaryLabel = underArt.mixed(with: ThemeRGB(red: 235, green: 235, blue: 245), amount: 0.6)
        for text in [white, secondaryLabel, tokens.accentText] {
            #expect(underArt.contrast(with: text) >= 4.5, "\(text)")
        }
    }

    // MARK: Layout

    /// A screen and its insets.
    private struct Screen {
        var size: CGSize
        var top: CGFloat
        var bottom: CGFloat
    }

    private static let screens = [
        Screen(size: CGSize(width: 402, height: 874), top: 59, bottom: 34),
        Screen(size: CGSize(width: 1024, height: 1366), top: 24, bottom: 20),
        Screen(size: CGSize(width: 375, height: 667), top: 20, bottom: 0),
        Screen(size: CGSize(width: 320, height: 568), top: 20, bottom: 0),
        Screen(size: CGSize(width: 260, height: 700), top: 24, bottom: 0)
    ]

    @Test(arguments: [SamainLayout.Kind.soft, .full])
    func everyPieceStaysOnTheScreen(kind: SamainLayout.Kind) {
        for device in Self.screens {
            let screen = CGRect(origin: .zero, size: device.size)
            let pieces = SamainLayout.pieces(kind, in: device.size, topInset: device.top, bottomInset: device.bottom)
            #expect(!pieces.isEmpty, "\(device.size)")
            for piece in pieces { #expect(screen.contains(piece.frame), "\(piece.art) \(device.size)") }
        }
    }

    /// Rules 7 and 9: no art behind the status bar, the toolbar buttons (the navigation bar's own row) or the large title's text
    /// column; the candelabra and the bat stand on the home indicator's inset, below the tab bar.
    @Test func theSoftArtStaysOutOfTheChromeAndOfTheText() throws {
        let size = CGSize(width: 402, height: 874)
        let pieces = SamainLayout.pieces(.soft, in: size, topInset: 59, bottomInset: 34)
        #expect(pieces.map(\.art) == [.web, .candelabra, .bat])
        let web = try #require(pieces.first)
        #expect(web.mirrored && web.frame.maxX == size.width && web.frame.minY >= 59 + SamainLayout.navigationRow)
        for piece in pieces.dropFirst() { #expect(piece.frame.minY >= size.height - 34 && piece.frame.maxY <= size.height) }
        #expect(!pieces[1].frame.intersects(pieces[2].frame))
        // The web hangs in the trailing corner only; a leading column of title text is never under it.
        #expect(web.frame.width <= size.width * 0.2 + 1e-9)
    }

    @Test func aScreenWithoutAHomeIndicatorInsetHasTheWebAlone() {
        let pieces = SamainLayout.pieces(.soft, in: CGSize(width: 375, height: 667), topInset: 20, bottomInset: 0)
        #expect(pieces.map(\.art) == [.web])
    }

    @Test func theAbuseThemeHasMoreArtAndItsPumpkinsStandOnTheHomeIndicatorInset() throws {
        let size = CGSize(width: 402, height: 874)
        let pieces = SamainLayout.pieces(.full, in: size, topInset: 59, bottomInset: 34)
        let soft = SamainLayout.pieces(.soft, in: size, topInset: 59, bottomInset: 34)
        #expect(pieces.count > soft.count)
        #expect(Set(pieces.map(\.art)) == Set(SamainLayout.Art.allCases))
        for piece in pieces where [.pumpkin, .pumpkinPlain, .candelabra].contains(piece.art) {
            #expect(piece.frame.maxY == size.height - 34)
        }
        let candelabra = try #require(pieces.first { $0.art == .candelabra })
        #expect(!pieces.filter { $0.art == .pumpkin || $0.art == .pumpkinPlain }.contains { $0.frame.intersects(candelabra.frame) })
    }

    @Test func aNarrowOrShortColumnHasNoArt() {
        for kind in [SamainLayout.Kind.soft, .full] {
            #expect(SamainLayout.pieces(kind, in: CGSize(width: 200, height: 800), topInset: 20, bottomInset: 0).isEmpty)
            #expect(SamainLayout.pieces(kind, in: CGSize(width: 400, height: 300), topInset: 20, bottomInset: 0).isEmpty)
            #expect(SamainLayout.pieces(kind, in: .zero, topInset: 0, bottomInset: 0).isEmpty)
        }
    }

    // MARK: The witch of the packing

    @Test func theWitchEntersAndLeavesOutsideTheBandAndStandsInIt() throws {
        let area = CGSize(width: 402, height: 650)
        let start = try #require(SamainSweepLayout.frame(in: area, windowHeight: 874, progress: 0))
        let end = try #require(SamainSweepLayout.frame(in: area, windowHeight: 874, progress: 1))
        #expect(start.maxX <= 0 && end.minX >= area.width - 1e-9)
        for step in 0...20 {
            let frame = try #require(SamainSweepLayout.frame(in: area, windowHeight: 874, progress: Double(step) / 20))
            #expect(frame.minY >= 0 && frame.maxY <= area.height)
            #expect(frame.height <= SamainSweepLayout.maxHeight)
            #expect(abs(frame.width / frame.height - SamainSweepLayout.aspectRatio) < 1e-9)
        }
        // She walks from the leading edge to the trailing one.
        let middle = try #require(SamainSweepLayout.frame(in: area, windowHeight: 874, progress: 0.5))
        #expect(start.minX < middle.minX && middle.minX < end.minX)
    }

    @Test func theWitchIsAQuarterOfTheWindowAndNeverTallerThanTheBand() {
        #expect(SamainSweepLayout.height(window: 874, band: 650) == 218.5)
        #expect(SamainSweepLayout.height(window: 2000, band: 650) == SamainSweepLayout.maxHeight)
        #expect(SamainSweepLayout.height(window: 874, band: 100) == 100)
        #expect(SamainSweepLayout.frame(in: .zero, windowHeight: 874, progress: 0.5) == nil)
        #expect(SamainSweepLayout.frame(in: CGSize(width: 402, height: 650), windowHeight: 0, progress: 0.5) == nil)
        // A progress outside 0...1 (a late frame, a NaN) never moves her out of range.
        let area = CGSize(width: 402, height: 650)
        func frame(_ progress: Double) -> CGRect? { SamainSweepLayout.frame(in: area, windowHeight: 874, progress: progress) }
        #expect(frame(3) == frame(1))
        #expect(frame(.nan) == frame(0))
    }

    @Test func theWitchImageIsBundledWithTheLayoutsRatio() throws {
        let image = try #require(UIImage(named: "SamainWitchSweep"))
        #expect(abs(image.size.width / image.size.height - SamainSweepLayout.aspectRatio) < 0.02)
    }

    // MARK: Packing overlay

    /// Samain's packing is the witch, never Noël's elves; Noël's (and no theme at all) stays the elves.
    @Test(arguments: [
        (SeasonalTheme.spooktoberSoft, PackingOverlay.witch), (.spooktoberAbuse, .witch),
        (.noelSoft, .elves), (.noelAbuse, .elves)
    ])
    func samainPackingIsTheWitchAndNoelsTheElves(theme: SeasonalTheme, overlay: PackingOverlay) {
        #expect(PackingOverlay(theme: theme) == overlay)
        #expect(PackingOverlay(theme: nil) == .elves)
    }
}
