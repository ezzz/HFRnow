import XCTest
@testable import HFRswift

final class ThemeBrightnessTests: XCTestCase {
    private let brightnessKey = "theme_night_brightness"
    private var previousBrightness: Any?

    override func setUp() {
        super.setUp()
        previousBrightness = UserDefaults.standard.object(forKey: brightnessKey)
    }

    override func tearDown() {
        if let previousBrightness {
            UserDefaults.standard.set(previousBrightness, forKey: brightnessKey)
        } else {
            UserDefaults.standard.removeObject(forKey: brightnessKey)
        }
        super.tearDown()
    }

    func testDarkThemeBrightnessScalesNeutralSurface() {
        ThemeUserColorStore.storeBrightness(0.5, forKey: brightnessKey)
        let source = UIColor(
            red: 40.0 / 255.0,
            green: 40.0 / 255.0,
            blue: 40.0 / 255.0,
            alpha: 0.8
        )

        let adjusted = ThemeUserColorStore.adjustedDarkThemeColor(
            source,
            minimumWhiteLevel: 0
        )

        assertRGB(
            adjusted,
            red: 20.0 / 255.0,
            green: 20.0 / 255.0,
            blue: 20.0 / 255.0,
            alpha: 0.8
        )
    }

    func testDarkThemeBrightnessPreservesMinimumSurfaceLevel() {
        ThemeUserColorStore.storeBrightness(0, forKey: brightnessKey)
        let source = UIColor(
            red: 46.0 / 255.0,
            green: 47.0 / 255.0,
            blue: 51.0 / 255.0,
            alpha: 1
        )

        let adjusted = ThemeUserColorStore.adjustedDarkThemeColor(
            source,
            minimumWhiteLevel: 20
        )

        assertRGB(
            adjusted,
            red: 20.0 / 255.0,
            green: 20.0 / 255.0,
            blue: 20.0 / 255.0,
            alpha: 1
        )
    }

    private func assertRGB(
        _ color: UIColor,
        red expectedRed: CGFloat,
        green expectedGreen: CGFloat,
        blue expectedBlue: CGFloat,
        alpha expectedAlpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            file: file,
            line: line
        )
        XCTAssertEqual(red, expectedRed, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(green, expectedGreen, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(blue, expectedBlue, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.002, file: file, line: line)
    }
}
