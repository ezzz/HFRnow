import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// The app-wide type scale and list density (LOT-169).
@MainActor
struct TextScaleTests {
    private let styles: [Font.TextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .footnote, .caption, .caption2
    ]
    private let percents = Array(stride(from: 70, through: 130, by: 5))

    @Test func thePercentageMultipliesTheSystemSizeOfEveryStyle() {
        for style in styles {
            let traits = UITraitCollection(preferredContentSizeCategory: .large)
            let system = UIFont.preferredFont(forTextStyle: style.uiTextStyle, compatibleWith: traits).pointSize
            #expect(abs(TextScale(percent: 70).pointSize(style, at: .large) - system * 0.7) < 0.001, "\(style)")
            #expect(TextScale.standard.pointSize(style, at: .large) == system, "\(style)")
            #expect(abs(TextScale(percent: 130).pointSize(style, at: .large) - system * 1.3) < 0.001, "\(style)")
        }
    }

    @Test func seventyPercentIsSmallerThanTheDefault() {
        for style in styles {
            #expect(TextScale(percent: 70).pointSize(style, at: .large) < TextScale.standard.pointSize(style, at: .large))
        }
    }

    @Test func accessibilitySizesStillGrowTheTextAtEverySliderValue() {
        let sizes: [DynamicTypeSize] = [.large, .xLarge, .xxxLarge, .accessibility1, .accessibility2, .accessibility3,
                                        .accessibility4, .accessibility5]
        for percent in percents {
            let scale = TextScale(percent: percent)
            let body = sizes.map { scale.pointSize(.body, at: $0) }
            #expect(zip(body, body.dropFirst()).allSatisfy { $0 < $1 }, "\(percent) %: \(body)")
        }
        // The smallest slider value at the largest accessibility size stays above the largest at the default size.
        #expect(TextScale(percent: 70).pointSize(.body, at: .accessibility5) > TextScale(percent: 130).pointSize(.body, at: .large))
    }

    @Test func metricsFollowThePercentage() {
        #expect(TextScale(percent: 70).scaled(40) == 28)
        #expect(TextScale.standard.scaled(40) == 40)
    }

    @Test func theSettingsModelDrivesTheScaleAndTheDensity() {
        let model = GeneralSettingsModel(store: InMemorySettingsStore())
        #expect(model.textScale == .standard)
        #expect(model.listDensity == .regular)
        model.textSizePercent = 70
        model.compactMode = true
        #expect(model.textScale == TextScale(percent: 70))
        #expect(model.listDensity == .compact)
        model.textSizePercent = 40 // clamped by the model
        #expect(model.textScale == TextScale(percent: 70))
    }

    @Test func compactRowsAreDenserOnEveryAxis() {
        let regular = ListDensity(compactMode: false)
        let compact = ListDensity(compactMode: true)
        #expect(regular == .regular)
        #expect(compact == .compact)
        #expect(compact.rowInsets.top == 3 && compact.rowInsets.bottom == 3) // legacy FavoritesListDensity
        #expect(compact.rowInsets.top < regular.rowInsets.top && compact.rowInsets.leading < regular.rowInsets.leading)
        #expect(compact.minimumRowHeight < regular.minimumRowHeight)
        #expect(compact.titleLineLimit < regular.titleLineLimit)
        #expect(compact.lineSpacing < regular.lineSpacing)
        #expect(compact.markerSize < regular.markerSize)
        #expect(compact.avatarSize < regular.avatarSize)
        #expect(TextScale.standard.pointSize(compact.titleStyle, at: .large)
            < TextScale.standard.pointSize(regular.titleStyle, at: .large))
        #expect(compact.mergesMetaLines && !regular.mergesMetaLines)
    }

    @Test func theCompactConversationRowHasOneMetaLine() {
        #expect(MessageRowView.metaLine(who: "membre", lastPost: "autre · hier") == "membre · autre · hier")
        #expect(MessageRowView.metaLine(who: "membre", lastPost: "membre · hier") == "membre · hier")
        #expect(MessageRowView.metaLine(who: "membre", lastPost: "membre") == "membre")
        #expect(MessageRowView.metaLine(who: "Interlocuteurs multiples", lastPost: nil) == "Interlocuteurs multiples")
        #expect(MessageRowView.metaLine(who: "membre", lastPost: "") == "membre")
    }
}
