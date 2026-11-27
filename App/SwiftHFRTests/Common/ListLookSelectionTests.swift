@testable import SwiftHFR
import SwiftUI
import Testing

/// #1073 item 4: a selected row is a light accent tint in the classic look too, not the system's solid accent fill.
struct ListLookSelectionTests {
    private static let schemes: [ColorScheme] = [.light, .dark]
    private static let contrasts: [ColorSchemeContrast] = [.standard, .increased]

    @Test func classicSelectedRowDrawsTheLightTint() {
        for scheme in Self.schemes {
            for contrast in Self.contrasts {
                let strength = ListLook.selectedStrength(scheme: scheme, contrast: contrast)
                #expect(ListLook.classic.rowBackground(isSelected: true, scheme: scheme, contrast: contrast)
                    == Color.accentColor.opacity(strength))
                #expect(strength <= ListLook.maxSelectedStrength)
            }
        }
    }

    @Test func selectionStrengthIsPinned() {
        #expect(ListLook.selectedStrength(scheme: .light, contrast: .standard) == 0.20)
        #expect(ListLook.selectedStrength(scheme: .light, contrast: .increased) == 0.30)
        #expect(ListLook.selectedStrength(scheme: .dark, contrast: .standard) == 0.30)
        #expect(ListLook.selectedStrength(scheme: .dark, contrast: .increased) == 0.30)
    }

    @Test func selectionIsStrongerThanAStatePill() {
        for scheme in Self.schemes {
            for contrast in Self.contrasts {
                #expect(ListLook.selectedStrength(scheme: scheme, contrast: contrast)
                    > RowTint.strength(scheme: scheme, contrast: contrast))
            }
        }
    }

    @Test func unselectedRowsKeepTheirBackground() {
        #expect(ListLook.classic.rowBackground(isSelected: false, scheme: .light, contrast: .standard) == nil)
        #expect(ListLook.dense.rowBackground(isSelected: false, scheme: .dark, contrast: .increased) == DenseListLook.rowBackground)
    }

    @Test func aSelectedRowKeepsItsStatePill() {
        #expect(TopicRowCues.accent(flag: nil, isSuperFavorite: true) == .superFavorite)
        #expect(MessageRowView.rowTint(isUnread: true) != nil)
    }
}
