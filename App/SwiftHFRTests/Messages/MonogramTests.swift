@testable import SwiftHFR
import Testing

/// The placeholder of an avatar-less correspondent (#569): initials and colour are a pure function of the pseudo.
struct MonogramTests {
    @Test(arguments: [
        ("user1", "U"), ("Jean-Pierre", "JP"), ("jean pierre martin", "JP"), ("__x__", "X"), ("élodie", "É"), ("!!!", "?"), ("", "?")
    ])
    func initials(_ pseudo: String, _ expected: String) {
        #expect(Monogram(pseudo: pseudo).initials == expected)
    }

    @Test func colourIsDeterministicAndIgnoresCaseAndZeroWidthSpaces() {
        let reference = Monogram(pseudo: "user1")
        #expect(reference == Monogram(pseudo: "user1"))
        #expect(reference.hue == Monogram(pseudo: "USER1").hue)
        #expect(reference.hue == Monogram(pseudo: "us\u{200B}er1").hue)
        // A pinned value: the hash must not change between launches or versions (FNV-1a, not `Hashable`).
        #expect(reference.hue == 217.0 / 360)
        #expect(reference.background(dark: false) == Monogram(pseudo: "user1").background(dark: false))
    }

    @Test func differentPseudosSpreadOverTheHueCircle() {
        let hues = Set((0..<200).map { Monogram(pseudo: "user\($0)").hue })
        #expect(hues.count > 100)
    }

    @Test func initialsKeepFourAndAHalfToOneContrastOnEveryHue() {
        for dark in [false, true] {
            for step in 0..<360 {
                let monogram = Monogram(initials: "X", hue: Double(step) / 360)
                let ratio = Monogram.contrast(monogram.background(dark: dark), Monogram.foreground(dark: dark))
                #expect(ratio >= 4.5, "hue \(step) dark \(dark) gives \(ratio)")
            }
        }
    }

    @Test func lightAndDarkDiscsDiffer() {
        let monogram = Monogram(pseudo: "user1")
        #expect(monogram.background(dark: false) != monogram.background(dark: true))
    }
}
