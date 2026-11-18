import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #842: a gallery theme recolours the native lists through the shared modifiers of `ThemedList.swift`; Legacy is untouched.
@MainActor
@Suite(.serialized)
struct ThemedListTests {
    private func rgb(_ color: UIColor, dark: Bool) -> [Int] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }

    private func hex(_ value: Int) -> [Int] { [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF] }

    private func themedModel(dark: Bool = true) throws -> ThemeSettingsModel {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == "test-theme" }))
        model.mode = dark ? .dark : .light
        return model
    }

    // MARK: The colour rule

    /// Legacy has no list colours, so every modifier keeps its content as is (LOT-188: pixel-identical).
    @Test func legacyHasNoListColours() {
        #expect(ThemeAppearance.standard.listColors == nil)
        var darker = ThemeAppearance.standard
        darker.darkStyle = .oled
        #expect(darker.listColors == nil)
    }

    /// `themedListRow`, `themedSectionHeader` and `themedTitle` draw the test theme's tokens, per appearance.
    @Test func aThemeGivesTheListItsTokens() throws {
        let colors = try #require(try themedModel().appearance.listColors)
        let light: [(UIColor, Int)] = [
            (colors.row, 0xFFFFFF), (colors.selectedRow, 0xD0E4FF), (colors.separator, 0xC6C6C8), (colors.text, 0x1C1C1E),
            (colors.secondaryText, 0x5A5A60), (colors.sectionHeader, 0x4A4A50), (colors.title, 0x000000)
        ]
        let dark: [(UIColor, Int)] = [
            (colors.row, 0x1A2430), (colors.selectedRow, 0x2A3A50), (colors.separator, 0x3A4656), (colors.text, 0xF2F2F7),
            (colors.secondaryText, 0xB0B8C0), (colors.sectionHeader, 0xC0C8D0), (colors.title, 0xFFFFFF)
        ]
        for (color, value) in light { #expect(rgb(color, dark: false) == hex(value)) }
        for (color, value) in dark { #expect(rgb(color, dark: true) == hex(value)) }
    }

    // MARK: In a real list

    /// A dark inset-grouped list of tall rows, the first one selected or not, with or without `themedListRow`.
    private struct ListRoot: View {
        let model: ThemeSettingsModel
        var themed = true
        var selected = false
        /// The rows in a `ThemedSection` instead of each carrying `themedListRow`.
        var sectioned = false
        var body: some View {
            List {
                if sectioned {
                    ThemedSection("Section") { ForEach(0..<4, id: \.self) { _ in Text("").frame(height: 200) } }
                } else {
                    ForEach(0..<4, id: \.self) { index in
                        Text("").frame(height: 200)
                            .modifier(Row(themed: themed, isSelected: selected && index == 0))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .appTheme(model)
        }
    }

    private struct Row: ViewModifier {
        let themed: Bool
        let isSelected: Bool
        @ViewBuilder func body(content: Content) -> some View {
            if themed { content.themedListRow(isSelected: isSelected) } else { content }
        }
    }

    private func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// The RGB at `x`, `y` pt from the top of the window.
    private func pixel(of window: UIWindow, x: CGFloat, y: CGFloat) -> [Int] {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let cgImage = image.cgImage {
            let scale = image.scale, size = window.bounds.size
            // Bottom-left origin: move the wanted point onto the 1 x 1 canvas.
            let canvas = CGRect(
                x: -x * scale, y: -(size.height - y) * scale, width: size.width * scale, height: size.height * scale
            )
            context?.draw(cgImage, in: canvas)
        }
        return data.prefix(3).map(Int.init)
    }

    private func show(_ root: ListRoot) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return window
    }

    private func near(_ lhs: [Int], _ rhs: [Int]) -> Bool { zip(lhs, rhs).allSatisfy { abs($0 - $1) <= 2 } }

    /// The middle of the first row (a 200 pt row below the list's top margin) and of the third.
    private let firstRow = CGPoint(x: 150, y: 150), thirdRow = CGPoint(x: 150, y: 550)

    /// A themed row paints `surface` (#1A2430 dark), a selected one `selection` (#2A3A50); without the modifier, the same theme
    /// leaves the system card (#1C1C1E), so the test fails without the change.
    @Test func aThemedRowPaintsTheThemesSurfaceAndItsSelection() async throws {
        let model = try themedModel()
        let window = try show(ListRoot(model: model, selected: true))
        defer { window.isHidden = true }
        let painted = await until {
            near(pixel(of: window, x: thirdRow.x, y: thirdRow.y), hex(0x1A2430))
                && near(pixel(of: window, x: firstRow.x, y: firstRow.y), hex(0x2A3A50))
        }
        let row = pixel(of: window, x: thirdRow.x, y: thirdRow.y), selected = pixel(of: window, x: firstRow.x, y: firstRow.y)
        #expect(painted, "row \(row), selected \(selected)")
    }

    /// The control: the same list without the modifier keeps the system card, so the theme's colour comes from `themedListRow`.
    @Test func withoutTheModifierTheRowKeepsTheSystemCard() async throws {
        let model = try themedModel()
        let window = try show(ListRoot(model: model, themed: false))
        defer { window.isHidden = true }
        let card = await until { near(pixel(of: window, x: thirdRow.x, y: thirdRow.y), hex(0x1C1C1E)) }
        #expect(card, "row \(pixel(of: window, x: thirdRow.x, y: thirdRow.y))")
    }

    /// `ThemedSection` themes its rows: the third row of a section paints `surface`.
    @Test func aThemedSectionPaintsItsRows() async throws {
        let window = try show(ListRoot(model: try themedModel(), sectioned: true))
        defer { window.isHidden = true }
        let painted = await until { near(pixel(of: window, x: thirdRow.x, y: thirdRow.y), hex(0x1A2430)) }
        #expect(painted, "row \(pixel(of: window, x: thirdRow.x, y: thirdRow.y))")
    }

    /// Legacy: the modifier is there, but the row is the system card, as without it.
    @Test func underLegacyTheModifierChangesNoPixel() async throws {
        let model = ThemeSettingsModel(store: InMemorySettingsStore(["auto_theme": .int(0), "theme": .int(1)]))
        let window = try show(ListRoot(model: model, selected: true))
        defer { window.isHidden = true }
        let card = await until {
            window.traitCollection.userInterfaceStyle == .dark && near(pixel(of: window, x: thirdRow.x, y: thirdRow.y), hex(0x1C1C1E))
        }
        #expect(card, "row \(pixel(of: window, x: thirdRow.x, y: thirdRow.y))")
    }

    // MARK: The text styles, rendered

    /// The test theme with distinct dark text tokens, so a swatch tells each one from the system's white: title #C03030,
    /// section header #30C030, row text #3030C0, secondary text #C0C030.
    private func swatchAppearance() throws -> ThemeAppearance {
        var json = try #require(try JSONSerialization.jsonObject(with: ThemeFixtures.data("test-theme")) as? [String: Any])
        var variants = try #require(json["variants"] as? [String: Any])
        var dark = try #require(variants["dark"] as? [String: Any])
        dark["title"] = "#C03030"
        dark["sectionHeader"] = "#30C030"
        dark["textPrimary"] = "#3030C0"
        dark["textSecondary"] = "#C0C030"
        variants["dark"] = dark
        json["variants"] = variants
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        var appearance = ThemeAppearance.standard
        appearance.themeVariants = theme.variants
        return appearance
    }

    /// `content` filling a dark window, under `appearance`.
    private func showSwatch(_ content: some View, appearance: ThemeAppearance) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: content.environment(\.themeAppearance, appearance).ignoresSafeArea())
        window.isHidden = false
        return window
    }

    /// The primary and secondary styles of `role`'s modifier, as two halves of the window.
    private struct Halves: View {
        let role: SwatchRole
        var body: some View {
            let halves = HStack(spacing: 0) { Rectangle().fill(.primary); Rectangle().fill(.secondary) }
            switch role {
            case .header: halves.themedSectionHeader()
            case .title: halves.themedTitle()
            case .rowText: halves.themedRowText()
            }
        }
    }

    private func halvesShow(_ role: SwatchRole, appearance: ThemeAppearance, _ left: Int, _ right: Int) async throws -> Bool {
        let window = try showSwatch(Halves(role: role), appearance: appearance)
        defer { window.isHidden = true }
        return await until {
            near(pixel(of: window, x: 75, y: 350), hex(left)) && near(pixel(of: window, x: 225, y: 350), hex(right))
        }
    }

    /// Each text modifier draws its tokens at both levels (a header and the title keep their token for `.secondary` too);
    /// without the modifier both halves would be the system's white and grey.
    @Test func theTextModifiersDrawTheirTokens() async throws {
        let appearance = try swatchAppearance()
        #expect(try await halvesShow(.header, appearance: appearance, 0x30C030, 0x30C030), "section header")
        #expect(try await halvesShow(.title, appearance: appearance, 0xC03030, 0xC03030), "title")
        #expect(try await halvesShow(.rowText, appearance: appearance, 0x3030C0, 0xC0C030), "row text")
    }

    /// Legacy: the same modifiers leave the system's primary, white in dark.
    @Test func underLegacyTheTextModifiersKeepTheSystemText() async throws {
        let window = try showSwatch(Halves(role: .header), appearance: .standard)
        defer { window.isHidden = true }
        let white = await until { near(pixel(of: window, x: 75, y: 350), hex(0xFFFFFF)) }
        #expect(white, "\(pixel(of: window, x: 75, y: 350))")
    }

    /// #651's read MP title takes the theme's `textSecondary`; Legacy keeps its own grey, never the theme's.
    @Test func aReadMPTitleTakesTheThemesSecondaryText() async throws {
        let appearance = try swatchAppearance()
        let themed = try showSwatch(Rectangle().fill(ReadTitleStyle()), appearance: appearance)
        defer { themed.isHidden = true }
        #expect(await until { near(pixel(of: themed, x: 150, y: 350), hex(0xC0C030)) }, "\(pixel(of: themed, x: 150, y: 350))")
        let legacy = try showSwatch(Rectangle().fill(ReadTitleStyle()), appearance: .standard)
        defer { legacy.isHidden = true }
        let grey = rgb(ReadTitleStyle.color(for: UITraitCollection(userInterfaceStyle: .dark)), dark: true)
        #expect(await until { near(pixel(of: legacy, x: 150, y: 350), grey) }, "\(pixel(of: legacy, x: 150, y: 350))")
    }

    /// Error text on a row: the system red under Legacy (#FF453A in dark), the app's accessible red under a theme (#FF827A).
    @Test func errorTextIsTheSystemRedForLegacyAndTheAccessibleRedUnderATheme() async throws {
        let themed = try showSwatch(Rectangle().fill(.themedError), appearance: try swatchAppearance())
        defer { themed.isHidden = true }
        #expect(await until { near(pixel(of: themed, x: 150, y: 350), hex(0xFF827A)) }, "\(pixel(of: themed, x: 150, y: 350))")
        let legacy = try showSwatch(Rectangle().fill(.themedError), appearance: .standard)
        defer { legacy.isHidden = true }
        #expect(await until { near(pixel(of: legacy, x: 150, y: 350), hex(0xFF453A)) }, "\(pixel(of: legacy, x: 150, y: 350))")
    }

    /// A short list in a sheet on a plain stack: below its one row, `themedListScreen` shows the theme's `background`
    /// (#101820 dark); Legacy keeps the system's grouped background (black in dark).
    @Test func aListScreenShowsTheThemesBackgroundAndLegacyTheSystems() async throws {
        func screen() -> some View { NavigationStack { List { Text("") }.themedListScreen() } }
        let themed = try showSwatch(screen(), appearance: try swatchAppearance())
        defer { themed.isHidden = true }
        #expect(await until { near(pixel(of: themed, x: 150, y: 650), hex(0x101820)) }, "\(pixel(of: themed, x: 150, y: 650))")
        let legacy = try showSwatch(screen(), appearance: .standard)
        defer { legacy.isHidden = true }
        #expect(await until { near(pixel(of: legacy, x: 150, y: 650), hex(0x000000)) }, "\(pixel(of: legacy, x: 150, y: 650))")
    }

    /// Legacy keeps Bookmarks' selection through `legacySelection`: a selected row shows that colour, an unselected one the card.
    @Test func underLegacyALegacySelectionStillPaintsTheSelectedRow() async throws {
        func row(selected: Bool) -> some View {
            List {
                ForEach(0..<4, id: \.self) { _ in
                    Text("").frame(height: 200).themedListRow(isSelected: selected, legacySelection: Color(red: 1, green: 0, blue: 0))
                }
            }
            .listStyle(.insetGrouped)
        }
        let selected = try showSwatch(row(selected: true), appearance: .standard)
        defer { selected.isHidden = true }
        #expect(await until { near(pixel(of: selected, x: thirdRow.x, y: thirdRow.y), hex(0xFF0000)) })
        let plain = try showSwatch(row(selected: false), appearance: .standard)
        defer { plain.isHidden = true }
        #expect(await until { near(pixel(of: plain, x: thirdRow.x, y: thirdRow.y), hex(0x1C1C1E)) })
    }

    /// The `errorText` of the contrast rules is the app's error colour, so the rule checks what a themed row draws.
    @Test func theErrorTextRuleIsTheAppsErrorColour() throws {
        let tokens = try #require(try ThemeFixtures.testTheme().variants?.light)
        for dark in [false, true] {
            let app = AccessibleColors.rgb(.errorText, dark: dark)
            #expect(tokens.color(named: "errorText", inLight: !dark) == ThemeRGB(red: app.red, green: app.green, blue: app.blue))
        }
    }
}

/// Which text modifier a swatch of `ThemedListTests` carries.
private enum SwatchRole { case header, title, rowText }
