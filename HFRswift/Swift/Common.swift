//
//  Common.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import Foundation
import Combine
import SwiftUI
import UIKit

extension Favorite: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Topic: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Forum: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

enum RootTabIdentifier: Int {
    case categories = 0
    case favorites = 1
    case messages = 2
    case more = 3
}

enum AppStartupScreen {
    static let storageKey = "HFRswiftStartupScreen"
    static let categoriesTabValue = "tab:categories"
    static let favoritesTabValue = "tab:favorites"
    static let messagesTabValue = "tab:messages"
    static let defaultValue = favoritesTabValue

    static func rootTab(for rawValue: String?) -> RootTabIdentifier {
        guard let rawValue, !rawValue.isEmpty else { return .favorites }

        switch rawValue {
        case categoriesTabValue:
            return .categories
        case messagesTabValue:
            return .messages
        case favoritesTabValue:
            fallthrough
        default:
            return .favorites
        }
    }
}

enum MessagesNotificationNavigation {
    static let openMessagesNotification = Notification.Name("HFRswiftOpenMessagesFromNotification")
    static let pendingOpenMessagesDefaultsKey = "HFRswiftOpenMessagesFromNotificationPending"
    static let notificationDestinationKey = "destination"
    static let messagesDestinationValue = "messages"

    static func consumePendingOpenMessagesRequest(defaults: UserDefaults = .standard) -> Bool {
        let hasPendingRequest = defaults.bool(forKey: pendingOpenMessagesDefaultsKey)
        guard hasPendingRequest else { return false }
        defaults.removeObject(forKey: pendingOpenMessagesDefaultsKey)
        return true
    }
}

extension Notification.Name {
    static let rootTabReselected = Notification.Name("HFRswiftRootTabReselectedNotification")
}

enum AppHaptics {
    private static let enabledKey = "haptics"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.object(forKey: enabledKey) else { return true }
        if let boolValue = rawValue as? Bool { return boolValue }
        if let numberValue = rawValue as? NSNumber { return numberValue.boolValue }
        if let stringValue = rawValue as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        return true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    static func refreshStarted() {
        impact(.light)
    }

    static func refreshCompleted() {
        impact(.light)
    }
}

@objc(HFRSwiftAlertPresenter)
final class HFRSwiftAlertPresenter: NSObject {
    @objc(displayTransientAlertWithTitle:message:duration:)
    static func displayTransientAlert(title: String?, message: String?, duration: Int) {
        guard let presenter = topViewController() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        presenter.present(alert, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(duration, 0))) {
                alert.dismiss(animated: true)
            }
        }
    }

    @objc(displayOKAlertWithTitle:message:)
    static func displayOKAlert(title: String, message: String?) {
        guard let presenter = topViewController() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    @objc(displayOKCancelAlertWithTitle:message:okHandler:cancelHandler:)
    static func displayOKCancelAlert(
        title: String,
        message: String?,
        okHandler: ((UIAlertAction) -> Void)?,
        cancelHandler: ((UIAlertAction) -> Void)?
    ) {
        guard let presenter = topViewController() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: okHandler))
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel, handler: cancelHandler))
        presenter.present(alert, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let rootController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        var controller = rootController
        while let presentedController = controller?.presentedViewController {
            controller = presentedController
        }
        return controller
    }
}

enum AppScreenRotation {
    static let legacyKey = "landscape_mode"
    static let enabledValue = "galerie_message"
    static let disabledValue = "none"

    static var isEnabled: Bool {
        let rawValue = UserDefaults.standard.string(forKey: legacyKey)
        return rawValue != disabledValue
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled ? enabledValue : disabledValue, forKey: legacyKey)
        HFRSwiftOrientationPolicy.refreshSupportedOrientations()
    }
}

@objc(HFRSwiftOrientationPolicy)
final class HFRSwiftOrientationPolicy: NSObject {
    private static var answerViewLockCount = 0

    @objc static func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return .all
        }
        guard AppScreenRotation.isEnabled else {
            return .portrait
        }
        return answerViewLockCount > 0 ? .portrait : .allButUpsideDown
    }

    static func lockForAnswerViewIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        answerViewLockCount += 1
        refreshSupportedOrientations()
    }

    static func unlockForAnswerViewIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        answerViewLockCount = max(answerViewLockCount - 1, 0)
        refreshSupportedOrientations()
    }

    static func refreshSupportedOrientations() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.windows.forEach {
                $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }

            if #available(iOS 16.0, *) {
                windowScene.requestGeometryUpdate(
                    .iOS(interfaceOrientations: supportedInterfaceOrientations())
                )
            }
        }
    }
}

enum AppLayoutCompactMode {
    static let key = "compact_mode"
}

enum AppTabBarMinimizeOnScroll {
    static let key = "tabbar_minimize_on_scroll"
}

enum AppTopicPageSwipeNavigation {
    static let key = "topic_page_swipe_navigation"
}

enum AppReplyButtonBehavior: String, CaseIterable, Identifiable {
    static let key = "reply_button_behavior"
    static let defaultValue = quick.rawValue

    case quick
    case forum
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick:
            return "Réponse rapide"
        case .forum:
            return "Répondre comme le forum"
        case .hidden:
            return "Pas d'icône"
        }
    }
}

enum AppTextSizeScale: Int, CaseIterable, Identifiable {
    static let key = "text_size_scale"

    case standard = 100
    case plus10 = 110
    case plus20 = 120
    case plus30 = 130

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .plus10:
            return "+10%"
        case .plus20:
            return "+20%"
        case .plus30:
            return "+30%"
        }
    }

    var factor: CGFloat {
        CGFloat(rawValue) / 100
    }

    static func value(for rawValue: Int) -> AppTextSizeScale {
        AppTextSizeScale(rawValue: rawValue) ?? .standard
    }

    static func scaledUIFont(
        textStyle: UIFont.TextStyle,
        basePointSize: CGFloat,
        rawValue: Int,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: basePointSize * value(for: rawValue).factor, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont)
    }
}

extension View {
    @ViewBuilder
    func compactListSectionSpacing(_ isCompactModeEnabled: Bool, spacing compactSpacing: CGFloat, regularSpacing: CGFloat? = nil) -> some View {
        if isCompactModeEnabled {
            self.listSectionSpacing(.custom(compactSpacing))
        } else if let regularSpacing {
            self.listSectionSpacing(.custom(regularSpacing))
        } else {
            self
        }
    }
}

enum AppThemeResolver {
    static let autoThemeKey = "auto_theme"
    static let manualThemeKey = "theme"
    static let autoThemeIOSValue = 3
    static let autoThemeManualValue = 0
    static let lightThemeValue = 0
    static let darkThemeValue = 1

    private static let deprecatedThemeKeys = [
        "force_manual_theme",
        "auto_theme_day_time",
        "auto_theme_night_time"
    ]

    static var usesSystemColorScheme: Bool {
        UserDefaults.standard.integer(forKey: autoThemeKey) == autoThemeIOSValue
    }

    @discardableResult
    static func normalizeThemeDefaultsIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        let autoTheme = defaults.integer(forKey: autoThemeKey)
        guard autoTheme != autoThemeManualValue, autoTheme != autoThemeIOSValue else {
            return false
        }
        defaults.set(autoThemeIOSValue, forKey: autoThemeKey)
        return true
    }

    @discardableResult
    static func removeDeprecatedThemeKeysIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        var didRemoveKey = false
        for key in deprecatedThemeKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            didRemoveKey = true
        }
        return didRemoveKey
    }

    static func setManualLegacyThemeValue(_ themeValue: Int, defaults: UserDefaults = .standard) {
        defaults.set(autoThemeManualValue, forKey: autoThemeKey)
        defaults.set(themeValue == darkThemeValue ? darkThemeValue : lightThemeValue, forKey: manualThemeKey)
        defaults.removeObject(forKey: "force_manual_theme")
    }

    static func setUsesSystemColorScheme(defaults: UserDefaults = .standard) {
        defaults.set(autoThemeIOSValue, forKey: autoThemeKey)
        _ = removeDeprecatedThemeKeysIfNeeded(defaults: defaults)
    }

    static func preferredColorScheme() -> ColorScheme? {
        guard !usesSystemColorScheme else { return nil }
        let manualTheme = UserDefaults.standard.integer(forKey: manualThemeKey)
        return manualTheme == darkThemeValue ? .dark : .light
    }

    static func currentColorScheme() -> ColorScheme {
        resolvedColorScheme()
    }

    static func resolvedColorScheme(systemColorScheme: ColorScheme? = nil) -> ColorScheme {
        if usesSystemColorScheme {
            return systemColorScheme ?? currentSystemColorScheme()
        }
        return preferredColorScheme() ?? .light
    }

    static func resolvedColorScheme(traitCollection: UITraitCollection?) -> ColorScheme {
        if usesSystemColorScheme {
            let style = traitCollection?.userInterfaceStyle ?? currentSystemUserInterfaceStyle()
            return style == .dark ? .dark : .light
        }
        return preferredColorScheme() ?? .light
    }

    static func preferredUIKitOverrideStyle() -> UIUserInterfaceStyle {
        guard let preferredColorScheme = preferredColorScheme() else {
            return .unspecified
        }
        return preferredColorScheme.uiUserInterfaceStyle
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        let style = currentSystemUserInterfaceStyle()
        return style == .dark ? .dark : .light
    }

    private static func currentSystemUserInterfaceStyle() -> UIUserInterfaceStyle {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?
            .traitCollection.userInterfaceStyle
        ?? UITraitCollection.current.userInterfaceStyle
    }
}

private extension Notification.Name {
    static let legacyThemeChanged = Notification.Name("kThemeChangedNotification")
}

@objc(HFRThemeBridge)
final class HFRThemeBridge: NSObject {
    @objc(normalizeThemeDefaultsIfNeeded)
    @discardableResult
    class func normalizeThemeDefaultsIfNeeded() -> Bool {
        AppThemeResolver.normalizeThemeDefaultsIfNeeded()
    }

    @objc(removeDeprecatedThemeKeysIfNeeded)
    @discardableResult
    class func removeDeprecatedThemeKeysIfNeeded() -> Bool {
        AppThemeResolver.removeDeprecatedThemeKeysIfNeeded()
    }

    @objc(resolvedLegacyThemeValue)
    class func resolvedLegacyThemeValue() -> Int {
        AppThemeResolver.currentColorScheme().legacyThemeValue
    }

    @objc(resolvedLegacyThemeValueForTraitCollection:)
    class func resolvedLegacyThemeValue(for traitCollection: UITraitCollection?) -> Int {
        AppThemeResolver.resolvedColorScheme(traitCollection: traitCollection).legacyThemeValue
    }

    @objc(setManualLegacyThemeValue:)
    class func setManualLegacyThemeValue(_ themeValue: Int) {
        AppThemeResolver.setManualLegacyThemeValue(themeValue)
    }

    @objc(setUsesSystemColorScheme)
    class func setUsesSystemColorScheme() {
        AppThemeResolver.setUsesSystemColorScheme()
    }

    @objc(preferredUIKitOverrideStyle)
    class func preferredUIKitOverrideStyle() -> UIUserInterfaceStyle {
        AppThemeResolver.preferredUIKitOverrideStyle()
    }
}

@objc(ThemeUserColorStore)
final class ThemeUserColorStore: NSObject {
    private static let noelDisabledKey = "theme_noel_disabled"
    private static let dayActionColorKey = "theme_day_color_action"
    private static let nightActionColorKey = "theme_night_color_action"
    private static let dayLoveColorKey = "theme_day_color_love"
    private static let nightLoveColorKey = "theme_night_color_love"
    private static let daySuperFavoriteColorKey = "theme_day_color_superfavori"
    private static let nightSuperFavoriteColorKey = "theme_night_color_superfavori"
    private static let nightBrightnessKey = "theme_night_brightness"

    @objc(storedColorForKey:)
    class func storedColor(forKey key: String) -> UIColor? {
        guard let serializedColor = UserDefaults.standard.string(forKey: key), !serializedColor.isEmpty else {
            return nil
        }
        return color(from: serializedColor)
    }

    @objc(storeColor:forKey:)
    class func storeColor(_ color: UIColor, forKey key: String) {
        UserDefaults.standard.set(serializedColor(from: color), forKey: key)
    }

    @objc(defaultColorForKey:)
    class func defaultColor(forKey key: String) -> UIColor? {
        switch key {
        case dayActionColorKey:
            return defaultTintColor(forLegacyThemeValue: 0)
        case nightActionColorKey:
            return defaultTintColor(forLegacyThemeValue: 1)
        case dayLoveColorKey:
            return UIColor(hue: 0.9, saturation: 0.1, brightness: 1.0, alpha: 1.0)
        case nightLoveColorKey:
            return UIColor(hue: 0.9, saturation: 0.9, brightness: 0.3, alpha: 1.0)
        case daySuperFavoriteColorKey:
            return UIColor(hue: 0.13, saturation: 0.08, brightness: 1.0, alpha: 1.0)
        case nightSuperFavoriteColorKey:
            return UIColor(hue: 0.15, saturation: 1.0, brightness: 0.2, alpha: 1.0)
        default:
            return nil
        }
    }

    @objc(resetColorForKey:)
    class func resetColor(forKey key: String) -> UIColor? {
        guard let defaultColor = defaultColor(forKey: key) else {
            return nil
        }
        storeColor(defaultColor, forKey: key)
        return defaultColor
    }

    @objc(defaultTintColorForLegacyThemeValue:)
    class func defaultTintColor(forLegacyThemeValue themeValue: Int) -> UIColor {
        if themeValue == 1 {
            return UIColor(hue: 190.0 / 360.0, saturation: 0.70, brightness: 0.95, alpha: 1.0)
        }
        return UIColor(hue: 190.0 / 360.0, saturation: 0.65, brightness: 1.0, alpha: 1.0)
    }

    @objc(actionTintColorForLegacyThemeValue:)
    class func actionTintColor(forLegacyThemeValue themeValue: Int) -> UIColor {
        guard UserDefaults.standard.bool(forKey: noelDisabledKey) else {
            return .red
        }

        let key = themeValue == 1 ? nightActionColorKey : dayActionColorKey
        return storedColor(forKey: key) ?? defaultTintColor(forLegacyThemeValue: themeValue)
    }

    class func loveColor(forLegacyThemeValue themeValue: Int) -> UIColor {
        let key = themeValue == 1 ? nightLoveColorKey : dayLoveColorKey
        return storedColor(forKey: key) ?? defaultColor(forKey: key) ?? UIColor(hue: 0.9, saturation: 0.1, brightness: 1.0, alpha: 1.0)
    }

    @objc(dynamicActionTintColor)
    class func dynamicActionTintColor() -> UIColor {
        guard UserDefaults.standard.bool(forKey: noelDisabledKey) else {
            return .red
        }

        return UIColor { traitCollection in
            let themeValue = resolvedLegacyThemeValue(for: traitCollection)
            return actionTintColor(forLegacyThemeValue: themeValue)
        }
    }

    @objc(creditsCSSForLegacyThemeValue:)
    class func creditsCSS(forLegacyThemeValue themeValue: Int) -> String {
        if themeValue == 1 {
            return "body{background:rgba(30, 31, 33, 1);color: rgba(146, 147, 151, 1);} a{color: rgba(42, 153, 250, 1);} .ios7 h1 {background:rgba(36, 37, 41, 1);color: rgba(109, 109, 114, 1);}.ios7 ul, .ios7 p {background:rgba(30, 31, 33, 1);}"
        }
        return "body{background:#efeff4;}.ios7 h1 {background:#efeff4;color: rgba(109, 109, 114, 1);}.ios7 ul {background:#fff;}.ios7 ul, .ios7 p {background:#fff;}"
    }

    @objc(smileysCSSForLegacyThemeValue:)
    class func smileysCSS(forLegacyThemeValue themeValue: Int) -> String {
        if themeValue == 1 {
            return "body.ios7 {background:rgba(30, 31, 33, 1);} body.ios7 .button { background-image : none !important; background-color : rgba(255, 255, 255,0.2); border-bottom:1px solid rgb(68,70,77); } body.ios7 #container_ajax img.smile, body.ios7 #smileperso img.smile { background-image : none !important; background-color: rgba(255, 255, 255, 0.2); border-bottom:1px solid rgb(68,70,77); } body.ios7 .button.selected, body.ios7 #container_ajax img.smile.selected, body.ios7 #smileperso img.smile.selected { background-image : none !important; background-color:rgba(255,255,255,0.1); }"
        }
        return "body.ios7 {background:#bbc2c9;} body.ios7 .button { background-image : none !important; background-color : rgba(255,255,255,1); border-bottom:1px solid rgb(136,138,142); } body.ios7 #container_ajax img.smile, body.ios7 #smileperso img.smile { background-image : none !important; background-color: rgba(255,255,255,1); border-bottom:1px solid rgb(136,138,142); } body.ios7 .button.selected, body.ios7 #container_ajax img.smile.selected, body.ios7 #smileperso img.smile.selected { background-image : none !important; background-color:rgba(136,138,142,1); }"
    }

    @objc(defaultBrightnessForKey:)
    class func defaultBrightness(forKey key: String) -> CGFloat {
        switch key {
        case nightBrightnessKey:
            return 1.0
        default:
            return 0.0
        }
    }

    @objc(storedBrightnessForKey:)
    class func storedBrightness(forKey key: String) -> CGFloat {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return resetBrightness(forKey: key)
        }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    @objc(storeBrightness:forKey:)
    class func storeBrightness(_ brightness: CGFloat, forKey key: String) {
        UserDefaults.standard.set(Double(brightness), forKey: key)
    }

    @objc(resetBrightnessForKey:)
    class func resetBrightness(forKey key: String) -> CGFloat {
        let brightness = defaultBrightness(forKey: key)
        storeBrightness(brightness, forKey: key)
        return brightness
    }

    private class func resolvedLegacyThemeValue(for traitCollection: UITraitCollection?) -> Int {
        HFRThemeBridge.resolvedLegacyThemeValue(for: traitCollection)
    }

    private class func serializedColor(from color: UIColor) -> String {
        let resolvedColor = color.resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if !resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            if resolvedColor.getWhite(&white, alpha: &alpha) {
                red = white
                green = white
                blue = white
            }
        }

        return String(format: "{%.3f, %.3f, %.3f, %.3f}", red, green, blue, alpha)
    }

    private class func color(from serializedColor: String) -> UIColor? {
        let trimmed = serializedColor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return nil
        }

        let payload = trimmed.dropFirst().dropLast()
        let components = payload.components(separatedBy: ", ")
        guard components.count == 4 else {
            return nil
        }

        let values = components.compactMap { Double($0) }
        guard values.count == 4 else {
            return nil
        }

        return UIColor(
            red: values[0],
            green: values[1],
            blue: values[2],
            alpha: values[3]
        )
    }
}

private extension ColorScheme {
    var legacyThemeValue: Int {
        self == .dark ? AppThemeResolver.darkThemeValue : AppThemeResolver.lightThemeValue
    }

    var uiUserInterfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}

private extension UIColor {
    func cssRGBA(alpha requestedAlpha: CGFloat) -> String {
        let resolvedColor = resolvedColor(with: UITraitCollection(userInterfaceStyle: .unspecified))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if !resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            if resolvedColor.getWhite(&white, alpha: &alpha) {
                red = white
                green = white
                blue = white
            }
        }

        let alphaValue = Double((requestedAlpha * 100).rounded() / 100)
        return "rgba(\(Int((red * 255).rounded())), \(Int((green * 255).rounded())), \(Int((blue * 255).rounded())), \(alphaValue))"
    }
}

struct AppThemePalette {
    let colorScheme: ColorScheme
    let actionTintUIColor: UIColor

    var actionTintColor: Color {
        Color(uiColor: actionTintUIColor)
    }

    var editorBackgroundColor: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    var controlBackgroundColor: Color {
        Color(uiColor: .tertiarySystemFill)
    }

    var tertiaryBackgroundColor: Color {
        Color(uiColor: .tertiarySystemBackground)
    }

    var webViewBackdropUIColor: UIColor {
        colorScheme == .dark ? .black : .systemGray6
    }

    var webViewBackdropColor: Color {
        Color(uiColor: webViewBackdropUIColor)
    }

    var staticPageBackgroundUIColor: UIColor {
        if colorScheme == .dark {
            return UIColor(red: 30.0 / 255.0, green: 31.0 / 255.0, blue: 33.0 / 255.0, alpha: 1.0)
        }
        return .systemGroupedBackground
    }

    var messageLoveUIColor: UIColor {
        ThemeUserColorStore.loveColor(forLegacyThemeValue: colorScheme == .dark ? 1 : 0)
    }

    func messageActionTintCSS(alpha: CGFloat) -> String {
        actionTintUIColor.cssRGBA(alpha: alpha)
    }

    func messageLoveCSS(alpha: CGFloat) -> String {
        messageLoveUIColor.cssRGBA(alpha: alpha)
    }

    var messageClassicHeaderBackgroundCSS: String {
        let color: UIColor
        if colorScheme == .dark {
            color = UIColor(red: 30.0 / 255.0, green: 31.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0)
        } else {
            color = UIColor(red: 244.0 / 255.0, green: 244.0 / 255.0, blue: 244.0 / 255.0, alpha: 1.0)
        }
        return color.cssRGBA(alpha: 1.0)
    }

    var stickyAccentColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.95, green: 0.49, blue: 0.25)
        }
        return Color(red: 0.91, green: 0.30, blue: 0.24)
    }

    var superFavoriteBackgroundColor: Color {
        Color(red: 0.98, green: 0.74, blue: 0.45)
            .opacity(colorScheme == .dark ? 0.28 : 0.18)
    }

    func unreadBadgeTextColor(isVisited: Bool) -> Color {
        colorScheme == .dark ? .black : .white
    }

    func unreadBadgeBackgroundColor(isVisited: Bool) -> Color {
        if colorScheme == .dark {
            return isVisited ? .white.opacity(0.55) : .white.opacity(0.78)
        }
        return isVisited ? .secondary.opacity(0.5) : .secondary
    }

    func topicFlagBackgroundColor(flagType: String?) -> Color? {
        guard
            let flagType = flagType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !flagType.isEmpty
        else {
            return nil
        }

        let opacity = colorScheme == .dark ? 0.18 : 0.12
        switch flagType {
        case "yellow":
            return Color.yellow.opacity(opacity + 0.02)
        case "blue":
            return Color.blue.opacity(opacity)
        case "red":
            return Color.red.opacity(opacity)
        default:
            return nil
        }
    }
}

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue = AppThemePalette(colorScheme: .light, actionTintUIColor: .systemBlue)
}

extension EnvironmentValues {
    var appThemePalette: AppThemePalette {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }
}

@MainActor
final class AppThemeStore: ObservableObject {
    static let shared = AppThemeStore()

    @Published private(set) var preferredColorScheme: ColorScheme?
    @Published private(set) var effectiveColorScheme: ColorScheme
    @Published private(set) var actionTintUIColor: UIColor
    @Published private(set) var themeRevision: Int

    var actionTintColor: Color {
        Color(uiColor: actionTintUIColor)
    }

    var palette: AppThemePalette {
        AppThemePalette(colorScheme: effectiveColorScheme, actionTintUIColor: actionTintUIColor)
    }

    var resolvedLegacyTheme: Theme {
        effectiveColorScheme == .dark ? ThemeDark : ThemeLight
    }

    private var lastKnownSystemColorScheme: ColorScheme?
    private var themeChangeObserver: NSObjectProtocol?

    private init() {
        let didNormalize = AppThemeResolver.normalizeThemeDefaultsIfNeeded()
        let didCleanup = AppThemeResolver.removeDeprecatedThemeKeysIfNeeded()
        if didNormalize || didCleanup {
            UserDefaults.standard.synchronize()
        }

        let initialColorScheme = AppThemeResolver.currentColorScheme()
        self.preferredColorScheme = AppThemeResolver.preferredColorScheme()
        self.effectiveColorScheme = initialColorScheme
        self.actionTintUIColor = Self.resolvedActionTintUIColor(for: initialColorScheme)
        self.themeRevision = 0

        themeChangeObserver = NotificationCenter.default.addObserver(
            forName: .legacyThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let senderIsSelf = (notification.object as? AppThemeStore).map { sender in
                guard let self else { return false }
                return sender === self
            } ?? false

            Task { @MainActor [weak self] in
                guard let self else { return }
                if senderIsSelf {
                    return
                }
                self.refresh(forceThemeRevision: true, notifyLegacy: false)
            }
        }
    }

    func refresh(
        systemColorScheme: ColorScheme? = nil,
        forceThemeRevision: Bool = false,
        notifyLegacy: Bool = false
    ) {
        if let systemColorScheme {
            lastKnownSystemColorScheme = systemColorScheme
        } else if AppThemeResolver.usesSystemColorScheme {
            lastKnownSystemColorScheme = AppThemeResolver.currentColorScheme()
        }

        let resolvedPreferredColorScheme = AppThemeResolver.preferredColorScheme()
        let resolvedEffectiveColorScheme = AppThemeResolver.resolvedColorScheme(
            systemColorScheme: lastKnownSystemColorScheme
        )
        let resolvedActionTintUIColor = Self.resolvedActionTintUIColor(for: resolvedEffectiveColorScheme)

        var didChange = false

        if preferredColorScheme != resolvedPreferredColorScheme {
            preferredColorScheme = resolvedPreferredColorScheme
            didChange = true
        }

        if effectiveColorScheme != resolvedEffectiveColorScheme {
            effectiveColorScheme = resolvedEffectiveColorScheme
            didChange = true
        }

        if !actionTintUIColor.isEqual(resolvedActionTintUIColor) {
            actionTintUIColor = resolvedActionTintUIColor
            didChange = true
        }

        if didChange || forceThemeRevision {
            themeRevision += 1
            if notifyLegacy {
                NotificationCenter.default.post(name: .legacyThemeChanged, object: self)
            }
        }
    }

    private static func resolvedActionTintUIColor(for colorScheme: ColorScheme) -> UIColor {
        let legacyThemeValue = colorScheme == .dark ? 1 : 0
        return ThemeUserColorStore.actionTintColor(forLegacyThemeValue: legacyThemeValue)
    }
}

typealias FavoritesLoadCompletion = ([Favorite]?, Error?) -> Void
typealias TopicsLoadCompletion = ([Topic]?, Error?) -> Void
typealias ForumsLoadCompletion = ([Forum]?, Error?) -> Void

enum LegacyLoaderBridgeError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "\(name) is unavailable"
        }
    }
}

enum LegacyLoaderRuntime {
    static func instantiateController(named className: String) -> NSObject? {
        guard let controllerClass = NSClassFromString(className) as? NSObject.Type else {
            return nil
        }
        return controllerClass.init()
    }

    static func sharedObject(named className: String, selector selectorName: String = "shared") -> NSObject? {
        guard let objectClass = NSClassFromString(className) as? NSObject.Type else {
            return nil
        }
        let selector = NSSelectorFromString(selectorName)
        guard objectClass.responds(to: selector),
              let unmanaged = objectClass.perform(selector) else {
            return nil
        }
        return unmanaged.takeUnretainedValue() as? NSObject
    }
}

protocol ProfileFilterListManaging {
    func blacklistProfiles() -> [String]
    func whitelistProfiles() -> [String]
    func isBlacklisted(_ pseudo: String) -> Bool
    func isWhitelisted(_ pseudo: String) -> Bool
    func addToBlacklist(_ pseudo: String) -> Bool
    func addToWhitelist(_ pseudo: String) -> Bool
    func removeFromBlacklist(_ pseudo: String) -> Bool
    func removeFromWhitelist(_ pseudo: String) -> Bool
    func toggleBlacklist(pseudo: String) -> String?
    func toggleWhitelist(pseudo: String) -> String?
}

final class ObjCProfileFilterListManager: ProfileFilterListManaging {
    static let shared = ObjCProfileFilterListManager()

    private let object: NSObject?

    init(object: NSObject? = LegacyLoaderRuntime.sharedObject(named: "BlackList")) {
        self.object = object
    }

    func blacklistProfiles() -> [String] {
        profiles(from: rawList(selectorName: "getBlackListForActiveCompte"))
    }

    func whitelistProfiles() -> [String] {
        profiles(from: rawList(selectorName: "getAllWhiteList"))
    }

    func isBlacklisted(_ pseudo: String) -> Bool {
        membershipStatus(pseudo: pseudo, selectorName: "isBL:")
    }

    func isWhitelisted(_ pseudo: String) -> Bool {
        membershipStatus(pseudo: pseudo, selectorName: "isWL:")
    }

    func addToBlacklist(_ pseudo: String) -> Bool {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty,
              let object,
              let function = boolFunction(selectorName: "addToBlackList:andSave:")
        else {
            return false
        }

        return function(object, NSSelectorFromString("addToBlackList:andSave:"), normalizedPseudo as NSString, true)
    }

    func addToWhitelist(_ pseudo: String) -> Bool {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty,
              let object,
              let function = voidFunction(selectorName: "addToWhiteList:")
        else {
            return false
        }

        function(object, NSSelectorFromString("addToWhiteList:"), normalizedPseudo as NSString)
        return true
    }

    func removeFromBlacklist(_ pseudo: String) -> Bool {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty,
              let object,
              let function = boolFunction(selectorName: "removeFromBlackList:andSave:")
        else {
            return false
        }

        return function(object, NSSelectorFromString("removeFromBlackList:andSave:"), normalizedPseudo as NSString, true)
    }

    func removeFromWhitelist(_ pseudo: String) -> Bool {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty,
              let object,
              let function = unaryBoolFunction(selectorName: "removeFromWhiteList:")
        else {
            return false
        }

        return function(object, NSSelectorFromString("removeFromWhiteList:"), normalizedPseudo as NSString)
    }

    func toggleBlacklist(pseudo: String) -> String? {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty else { return nil }

        if isBlacklisted(normalizedPseudo) {
            let success = removeFromBlacklist(normalizedPseudo)
            return success
                ? "\(normalizedPseudo) a été supprimé de la liste noire"
                : "Erreur! \(normalizedPseudo) n'a pas pu être supprimé de la liste noire"
        }

        let success = addToBlacklist(normalizedPseudo)
        return success
            ? "BIM! \(normalizedPseudo) ajouté à la liste noire"
            : "Erreur! \(normalizedPseudo) n'a pas pu être ajouté à la liste noire"
    }

    func toggleWhitelist(pseudo: String) -> String? {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty else { return nil }

        if isWhitelisted(normalizedPseudo) {
            _ = removeFromWhitelist(normalizedPseudo)
            return "OH NOES ! \(normalizedPseudo) a été supprimé de la love list"
        }

        guard addToWhitelist(normalizedPseudo) else { return nil }
        return "BOUM BOUM ! \(normalizedPseudo) ajouté à la love list \u{2665}"
    }

    private func rawList(selectorName: String) -> NSArray? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector) -> NSArray?
        let implementation = object.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(object, selector)
    }

    private func profiles(from rawList: NSArray?) -> [String] {
        (rawList as? [[AnyHashable: Any]])?
            .compactMap { entry in
                (entry["word"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty } ?? []
    }

    private func membershipStatus(pseudo: String, selectorName: String) -> Bool {
        let normalizedPseudo = normalizedPseudo(from: pseudo)
        guard !normalizedPseudo.isEmpty,
              let object,
              let function = unaryBoolFunction(selectorName: selectorName)
        else {
            return false
        }

        return function(object, NSSelectorFromString(selectorName), normalizedPseudo as NSString)
    }

    private func boolFunction(selectorName: String) -> (@convention(c) (AnyObject, Selector, NSString, Bool) -> Bool)? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }

        let implementation = object.method(for: selector)
        return unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector, NSString, Bool) -> Bool).self)
    }

    private func unaryBoolFunction(selectorName: String) -> (@convention(c) (AnyObject, Selector, NSString) -> Bool)? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }

        let implementation = object.method(for: selector)
        return unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector, NSString) -> Bool).self)
    }

    private func voidFunction(selectorName: String) -> (@convention(c) (AnyObject, Selector, NSString) -> Void)? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }

        let implementation = object.method(for: selector)
        return unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector, NSString) -> Void).self)
    }

    private func normalizedPseudo(from pseudo: String) -> String {
        pseudo
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

typealias LegacyRawCompte = [AnyHashable: Any]

struct LegacyAccountIdentity: Equatable {
    let pseudo: String
    let displayName: String

    var displayNameLowercased: String {
        displayName.lowercased()
    }
}

protocol LegacyAccountsManaging {
    func comptes() -> [LegacyRawCompte]
    func mainCompte() -> LegacyRawCompte?
    func currentPseudo() -> String?
    func currentAccountIdentity() -> LegacyAccountIdentity?
    func setMainPseudo(_ pseudo: String)
    func deletePseudo(at index: Int)
    func addCompte(pseudo: String, cookies: [HTTPCookie], avatar: Data?, hash: String?)
    func forceCookies(for compte: LegacyRawCompte)
    func setHash(_ hash: String, for compte: LegacyRawCompte)
}

final class ObjCLegacyAccountsManager: LegacyAccountsManaging {
    static let shared = ObjCLegacyAccountsManager()

    private let manager: NSObject?

    init(manager: NSObject? = LegacyLoaderRuntime.sharedObject(named: "MultisManager", selector: "sharedManager")) {
        self.manager = manager
    }

    func comptes() -> [LegacyRawCompte] {
        guard let manager else { return [] }
        let selector = NSSelectorFromString("getComtpes")
        guard manager.responds(to: selector) else { return [] }

        typealias Function = @convention(c) (AnyObject, Selector) -> NSArray?
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(manager, selector) as? [LegacyRawCompte] ?? []
    }

    func mainCompte() -> LegacyRawCompte? {
        guard let manager else { return nil }
        let selector = NSSelectorFromString("getMainCompte")
        guard manager.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector) -> NSDictionary?
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(manager, selector) as? LegacyRawCompte
    }

    func currentPseudo() -> String? {
        guard let manager else { return nil }
        let selector = NSSelectorFromString("getCurrentPseudo")
        guard manager.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector) -> NSString?
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(manager, selector) as String?
    }

    func currentAccountIdentity() -> LegacyAccountIdentity? {
        let mainCompte = mainCompte()
        let pseudo =
            normalizedString(currentPseudo()) ??
            normalizedString(mainCompte?["PSEUDO"]) ??
            normalizedString(mainCompte?["PSEUDO_DISPLAY"])

        guard let pseudo else {
            return nil
        }

        let displayName = normalizedString(mainCompte?["PSEUDO_DISPLAY"]) ?? pseudo
        return LegacyAccountIdentity(pseudo: pseudo, displayName: displayName)
    }

    func setMainPseudo(_ pseudo: String) {
        guard let manager else { return }
        let selector = NSSelectorFromString("setPseudoAsMain:")
        guard manager.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Void
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(manager, selector, pseudo as NSString)
    }

    func deletePseudo(at index: Int) {
        guard let manager else { return }
        let selector = NSSelectorFromString("deletePseudoAtIndex:")
        guard manager.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector, NSInteger) -> Void
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(manager, selector, index)
    }

    func addCompte(pseudo: String, cookies: [HTTPCookie], avatar: Data?, hash: String?) {
        guard let manager else { return }
        let selector = NSSelectorFromString("addCompteWithPseudo:andCookies:andAvatar:andHash:")
        guard manager.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector, NSString, NSArray, NSData?, NSString?) -> Void
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(manager, selector, pseudo as NSString, cookies as NSArray, avatar as NSData?, hash as NSString?)
    }

    func forceCookies(for compte: LegacyRawCompte) {
        guard let manager else { return }
        let selector = NSSelectorFromString("forceCookiesForCompte:")
        guard manager.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector, NSDictionary) -> Void
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(manager, selector, compte as NSDictionary)
    }

    func setHash(_ hash: String, for compte: LegacyRawCompte) {
        guard let manager else { return }
        let selector = NSSelectorFromString("setHashForCompte:andHash:")
        guard manager.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector, NSDictionary, NSString) -> Void
        let implementation = manager.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(manager, selector, compte as NSDictionary, hash as NSString)
    }

    private func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol LegacyMPStorageManaging {
    var isAvailable: Bool { get }
    func initializeOrResetMP(pseudo: String) -> Bool
    func parseBookmarks()
    func bookmarksCount() -> Int
    func bookmark(at index: Int) -> Bookmark?
    func bookmark(topicID: String, postID: String) -> Bookmark?
    func addBookmark(topicID: String, topicCategory: String, postID: String, title: String, author: String) -> Bool
    func removeBookmark(_ bookmark: Bookmark) -> Bool
    func reloadAsynchronously()
    func mpFlagURL(topicID: Int) -> String?
    func mpFlagPage(topicID: Int) -> Int?
    func updateMPFlag(topicID: Int, page: Int, p: String, href: String, uri: String)
}

final class ObjCMPStorageBridge: LegacyMPStorageManaging {
    static let shared = ObjCMPStorageBridge()

    private let storage: NSObject?

    init(storage: NSObject? = LegacyLoaderRuntime.sharedObject(named: "MPStorage")) {
        self.storage = storage
    }

    var isAvailable: Bool {
        storage != nil
    }

    func initializeOrResetMP(pseudo: String) -> Bool {
        guard let storage else { return false }
        let selector = NSSelectorFromString("initOrResetMP:")
        guard storage.responds(to: selector) else { return false }

        typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, pseudo as NSString)
    }

    func parseBookmarks() {
        guard let storage else { return }
        let selector = NSSelectorFromString("parseBookmarks")
        guard storage.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(storage, selector)
    }

    func bookmarksCount() -> Int {
        guard let storage else { return 0 }
        let selector = NSSelectorFromString("getBookmarksNumber")
        guard storage.responds(to: selector) else { return 0 }

        typealias Function = @convention(c) (AnyObject, Selector) -> Int32
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return Int(function(storage, selector))
    }

    func bookmark(at index: Int) -> Bookmark? {
        guard let storage else { return nil }
        let selector = NSSelectorFromString("getBookmarkAtIndex:")
        guard storage.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> AnyObject?
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, Int32(index)) as? Bookmark
    }

    func bookmark(topicID: String, postID: String) -> Bookmark? {
        guard let storage else { return nil }
        let selector = NSSelectorFromString("getBookmarkForPost:numreponse:")
        guard storage.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString) -> AnyObject?
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, topicID as NSString, postID as NSString) as? Bookmark
    }

    func addBookmark(topicID: String, topicCategory: String, postID: String, title: String, author: String) -> Bool {
        guard let bookmark = LegacyLoaderRuntime.instantiateController(named: "Bookmark") else {
            return false
        }

        bookmark.setValue(topicID, forKey: "sPost")
        bookmark.setValue(topicCategory, forKey: "sCat")
        bookmark.setValue(postID, forKey: "sNumResponse")
        bookmark.setValue(title, forKey: "sLabel")
        bookmark.setValue(author, forKey: "sAuthorPost")
        bookmark.setValue(Date(), forKey: "dateBookmarkCreation")

        return addBookmark(bookmark)
    }

    func removeBookmark(_ bookmark: Bookmark) -> Bool {
        guard let storage else { return false }
        let selector = NSSelectorFromString("removeBookmarkSynchronous:")
        guard storage.responds(to: selector) else { return false }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, bookmark)
    }

    private func addBookmark(_ bookmark: NSObject) -> Bool {
        guard let storage else { return false }
        let selector = NSSelectorFromString("addBookmarkSynchronous:")
        guard storage.responds(to: selector) else { return false }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, bookmark)
    }

    func reloadAsynchronously() {
        guard let storage else { return }
        let selector = NSSelectorFromString("reloadMPStorageAsynchronous")
        guard storage.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(storage, selector)
    }

    func mpFlagURL(topicID: Int) -> String? {
        guard let storage else { return nil }
        let selector = NSSelectorFromString("getUrlFlagForTopidId:")
        guard storage.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> NSString?
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        guard let url = function(storage, selector, Int32(topicID)) as String? else { return nil }
        return Self.relativeForumURLString(from: url)
    }

    func mpFlagPage(topicID: Int) -> Int? {
        guard let storage else { return nil }
        let selector = NSSelectorFromString("getPageFlagForTopidId:")
        guard storage.responds(to: selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> Int
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let page = function(storage, selector, Int32(topicID))
        return page > 0 ? page : nil
    }

    func updateMPFlag(topicID: Int, page: Int, p: String, href: String, uri: String) {
        guard let storage else { return }
        let selector = NSSelectorFromString("updateMPFlagAsynchronous:")
        guard storage.responds(to: selector) else { return }

        let flag: NSDictionary = [
            "post": NSNumber(value: topicID),
            "p": p,
            "href": href,
            "page": NSNumber(value: page),
            "uri": uri
        ]

        typealias Function = @convention(c) (AnyObject, Selector, NSDictionary) -> Void
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(storage, selector, flag)
    }

    private static func relativeForumURLString(from rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.lowercased() == "forum.hardware.fr"
        else {
            return trimmed
        }

        var relative = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            relative += "?\(query)"
        }
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            relative += "#\(fragment)"
        }
        return relative
    }
}

protocol FavoritesLoading {
    func fetchFavorites(completion: @escaping FavoritesLoadCompletion)
}

private enum LegacySessionPreparation {
    static func prepareCurrentAccountSession() {
        _ = try? ObjCAccountSessionService().makeReplySessionContext(cookieStorage: .shared)
    }
}

final class ObjCFavoritesLoader: FavoritesLoading {
    private let controller: NSObject?

    init(controller: NSObject? = LegacyLoaderRuntime.instantiateController(named: "ObjCFavoritesLoaderWorker")) {
        self.controller = controller
    }

    func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
        guard let controller else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCFavoritesLoaderWorker"))
            return
        }

        LegacySessionPreparation.prepareCurrentAccountSession()

        let selector = NSSelectorFromString("fetchContentWithCompletion:")
        guard controller.responds(to: selector) else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCFavoritesLoaderWorker.fetchContentWithCompletion"))
            return
        }

        typealias CompletionBlock = @convention(block) (NSArray?, NSError?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, CompletionBlock) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let block: CompletionBlock = { favorites, error in
            completion(favorites as? [Favorite], error)
        }
        function(controller, selector, block)
    }
}

protocol MPTopicsLoading {
    func fetchTopics(completion: @escaping TopicsLoadCompletion)
}

final class ObjCMPTopicsLoader: MPTopicsLoading {
    private let controller: NSObject?

    init(controller: NSObject? = LegacyLoaderRuntime.instantiateController(named: "ObjCMPTopicsLoaderWorker")) {
        self.controller = controller
    }

    func fetchTopics(completion: @escaping TopicsLoadCompletion) {
        guard let controller else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCMPTopicsLoaderWorker"))
            return
        }

        LegacySessionPreparation.prepareCurrentAccountSession()

        let selector = NSSelectorFromString("fetchContentWithCompletion:")
        guard controller.responds(to: selector) else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCMPTopicsLoaderWorker.fetchContentWithCompletion"))
            return
        }

        typealias CompletionBlock = @convention(block) (NSArray?, NSError?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, CompletionBlock) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let block: CompletionBlock = { topics, error in
            completion(topics as? [Topic], error)
        }
        function(controller, selector, block)
    }
}

protocol ForumsLoading {
    func fetchForums(completion: @escaping ForumsLoadCompletion)
}

final class ObjCForumsLoader: ForumsLoading {
    private let controller: NSObject?

    init(controller: NSObject? = LegacyLoaderRuntime.instantiateController(named: "ObjCForumsLoaderWorker")) {
        self.controller = controller
    }

    func fetchForums(completion: @escaping ForumsLoadCompletion) {
        guard let controller else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCForumsLoaderWorker"))
            return
        }

        let selector = NSSelectorFromString("fetchContentWithCompletion:")
        guard controller.responds(to: selector) else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCForumsLoaderWorker.fetchContentWithCompletion"))
            return
        }

        typealias CompletionBlock = @convention(block) (NSArray?, NSError?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, CompletionBlock) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let block: CompletionBlock = { forums, error in
            completion(forums as? [Forum], error)
        }
        function(controller, selector, block)
    }
}

enum TopicListFlag: Int {
    case all = 0
    case favorites = 1
    case tracked = 2
    case read = 3
}

protocol ForumTopicsLoading {
    func fetchTopics(for forum: Forum, flag: TopicListFlag, pageURL: String?, completion: @escaping ForumTopicsLoadCompletion)
}

extension ForumTopicsLoading {
    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping ForumTopicsLoadCompletion) {
        fetchTopics(for: forum, flag: flag, pageURL: nil, completion: completion)
    }
}

typealias ForumTopicsLoadCompletion = (ForumTopicsLoadResult?, Error?) -> Void

struct ForumTopicsLoadResult {
    let topics: [Topic]
    let newTopicURL: URL?
    let pageInfo: ForumSearchPageInfo
}

final class ObjCForumTopicsLoader: ForumTopicsLoading {
    private let controller: NSObject?

    init(controller: NSObject? = LegacyLoaderRuntime.instantiateController(named: "ObjCForumTopicsLoaderWorker")) {
        self.controller = controller
    }

    func fetchTopics(for forum: Forum, flag: TopicListFlag, pageURL: String?, completion: @escaping ForumTopicsLoadCompletion) {
        guard let controller else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCForumTopicsLoaderWorker"))
            return
        }

        LegacySessionPreparation.prepareCurrentAccountSession()

        let selector = NSSelectorFromString("fetchContentForForum:flagIndex:pageURL:completion:")
        guard controller.responds(to: selector) else {
            completion(nil, LegacyLoaderBridgeError.unavailable("ObjCForumTopicsLoaderWorker.fetchContentForForum"))
            return
        }

        typealias CompletionBlock = @convention(block) (NSArray?, NSError?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, Forum, NSInteger, NSString?, CompletionBlock) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let block: CompletionBlock = { topics, error in
            let resolvedTopics = topics as? [Topic] ?? []
            let newTopicURL = Self.absoluteForumURL(from: controller.value(forKey: "forumNewTopicUrl") as? String)
            let pageInfo = Self.pageInfo(from: controller, resultCount: resolvedTopics.count)
            completion(ForumTopicsLoadResult(topics: resolvedTopics, newTopicURL: newTopicURL, pageInfo: pageInfo), error)
        }
        function(controller, selector, forum, flag.rawValue, pageURL as NSString?, block)
    }

    private static func pageInfo(from controller: NSObject, resultCount: Int) -> ForumSearchPageInfo {
        let raw: NSDictionary = [
            "currentURL": stringValue(controller.value(forKey: "currentUrl")) ?? "",
            "nextPageURL": stringValue(controller.value(forKey: "nextPageUrl")) ?? "",
            "previousPageURL": stringValue(controller.value(forKey: "previousPageUrl")) ?? "",
            "firstPageURL": stringValue(controller.value(forKey: "firstPageUrl")) ?? "",
            "lastPageURL": stringValue(controller.value(forKey: "lastPageUrl")) ?? "",
            "pageNumber": numberValue(controller.value(forKey: "pageNumber")),
            "firstPageNumber": numberValue(controller.value(forKey: "firstPageNumber")),
            "lastPageNumber": numberValue(controller.value(forKey: "lastPageNumber")),
            "resultCount": resultCount
        ]
        return ForumSearchPageInfo(raw: raw)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
    }

    private static func numberValue(_ value: Any?) -> NSNumber {
        if let number = value as? NSNumber {
            return number
        }
        if let integer = value as? Int {
            return NSNumber(value: integer)
        }
        return NSNumber(value: 1)
    }

    private static func absoluteForumURL(from rawValue: String?) -> URL? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }
        let baseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr/")!
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }
}

struct TopicPageMessageActions: Equatable {
    let quoteURL: URL?
    let profileURL: URL?
    let privateMessageURL: URL?
    let avatarImagePath: String?
    let postID: String?
    let editURL: URL?
    let favoriteURL: URL?
    let alertURL: URL?
    let permalinkURL: URL?
    let authorName: String?
    let quoteJS: String?
    let isOwnMessage: Bool
    let canBeFavorite: Bool
    let isPrivateCategory: Bool
    let canAQ: Bool
    let canBookmark: Bool
    let canDelete: Bool
    let topicID: String?
    let topicCategory: String?
    let topicTitle: String?
}

struct TopicPageContent {
    let html: String
    let topicAnswerURL: URL?
    let currentPage: Int?
    let maxPage: Int?
    let messageActionsByIndex: [Int: TopicPageMessageActions]
    let topicTitle: String?
    let hasPoll: Bool
    let pollIsNewVote: Bool
    let pollData: PollData?
    let searchInputData: [String: String]

    init(
        html: String,
        topicAnswerURL: URL?,
        currentPage: Int? = nil,
        maxPage: Int? = nil,
        messageActionsByIndex: [Int: TopicPageMessageActions] = [:],
        topicTitle: String? = nil,
        hasPoll: Bool = false,
        pollIsNewVote: Bool = false,
        pollData: PollData? = nil,
        searchInputData: [String: String] = [:]
    ) {
        self.html = html
        self.topicAnswerURL = topicAnswerURL
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.messageActionsByIndex = messageActionsByIndex
        self.topicTitle = topicTitle
        self.hasPoll = hasPoll
        self.pollIsNewVote = pollIsNewVote
        self.pollData = pollData
        self.searchInputData = searchInputData
    }
}

enum TopicPageLoadingError: LocalizedError {
    case missingHTML

    var errorDescription: String? {
        switch self {
        case .missingHTML:
            return "No HTML returned for topic page"
        }
    }
}

protocol TopicPageLoading {
    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void)
    func cancelTopicPageFetch()
}

extension TopicPageLoading {
    func cancelTopicPageFetch() {}
}

enum LegacyTopicWorkerRuntime {
    static let className = "ObjCTopicPageWorker"

    enum SelectorName {
        static let cancelFetchContent = "cancelFetchContent"
        static let fetchContent = "fetchContentForTopicURL:anchor:completion:"
        static let messageActions = "swiftMessageActionsByIndex"
    }

    static func instantiate() -> NSObject? {
        LegacyLoaderRuntime.instantiateController(named: className)
    }

    static func unavailable(_ selectorName: String? = nil) -> LegacyLoaderBridgeError {
        if let selectorName {
            return .unavailable("\(className).\(selectorName)")
        }
        return .unavailable(className)
    }
}

struct TopicPageRefreshProbePolicy {
    let previousPage: Int
    let previousMaxPage: Int
    let loadedPage: Int
    let loadedMaxPage: Int
    let initialScrollToBottom: Bool

    var nextPageToProbe: Int? {
        guard initialScrollToBottom else { return nil }
        guard previousPage >= previousMaxPage else { return nil }
        guard loadedPage >= previousMaxPage else { return nil }
        guard loadedMaxPage <= previousMaxPage else { return nil }
        return previousMaxPage + 1
    }

    static func mergedMaxPage(currentMaxPage: Int, probeCurrentPage: Int?, probeMaxPage: Int?) -> Int {
        if let probeMaxPage {
            return max(currentMaxPage, max(probeMaxPage, 1))
        }
        return max(max(currentMaxPage, probeCurrentPage ?? 0), 1)
    }
}

final class ObjCTopicPageLoader: TopicPageLoading {
    private enum MessageActionKey {
        static let quoteURL = "quoteURL"
        static let profileURL = "profileURL"
        static let privateMessageURL = "privateMessageURL"
        static let avatarImagePath = "avatarImagePath"
        static let postID = "postID"
        static let editURL = "editURL"
        static let favoriteURL = "favoriteURL"
        static let alertURL = "alertURL"
        static let permalinkURL = "permalinkURL"
        static let authorName = "authorName"
        static let quoteJS = "quoteJS"
        static let isOwnMessage = "isOwnMessage"
        static let canBeFavorite = "canBeFavorite"
        static let isPrivateCategory = "isPrivateCategory"
        static let canAQ = "canAQ"
        static let canBookmark = "canBookmark"
        static let canDelete = "canDelete"
        static let topicID = "topicID"
        static let topicCategory = "topicCategory"
        static let topicTitle = "topicTitle"
    }

    private let controller: NSObject?

    init(controller: NSObject? = LegacyTopicWorkerRuntime.instantiate()) {
        self.controller = controller
    }

    func cancelTopicPageFetch() {
        guard let controller else { return }

        let selector = NSSelectorFromString(LegacyTopicWorkerRuntime.SelectorName.cancelFetchContent)
        guard controller.responds(to: selector) else { return }

        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(controller, selector)
    }

    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void) {
        guard let controller else {
            completion(.failure(LegacyTopicWorkerRuntime.unavailable()))
            return
        }

        let selector = NSSelectorFromString(LegacyTopicWorkerRuntime.SelectorName.fetchContent)
        guard controller.responds(to: selector) else {
            completion(.failure(LegacyTopicWorkerRuntime.unavailable("fetchContentForTopicURL")))
            return
        }

        // Match the legacy controller behavior: cancel any in-flight request before starting a new one.
        cancelTopicPageFetch()

        typealias CompletionBlock = @convention(block) (NSString?, NSString?, NSNumber?, NSNumber?, NSError?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString?, CompletionBlock) -> Void
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let block: CompletionBlock = { html, topicAnswerURL, currentPage, maxPage, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let html = html as String? else {
                completion(.failure(TopicPageLoadingError.missingHTML))
                return
            }
            let answerURL = (topicAnswerURL as String?).flatMap(URL.init(string:))
            let messageActionsByIndex = self.extractMessageActionsByIndex(from: controller)
            let topicTitle = (controller.value(forKey: "sNavigationViewTitle") as? String)
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? (controller.value(forKey: "_topicName") as? String)
                    .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let hasPoll = (controller.value(forKey: "swiftHasPoll") as? Bool) ?? false
            let pollIsNewVote = (controller.value(forKey: "swiftPollIsNewVote") as? Bool) ?? false
            let pollData = hasPoll
                ? (controller.value(forKey: "swiftPollHTML") as? String).flatMap { PollHTMLParser.parse(from: $0) }
                : nil
            let searchInputData = (controller.value(forKey: "swiftSearchInputData") as? [String: String]) ?? [:]
            print("[Poll] hasPoll=\(hasPoll) pollIsNewVote=\(pollIsNewVote) pollData=\(pollData != nil)")
            completion(.success(TopicPageContent(
                html: html,
                topicAnswerURL: answerURL,
                currentPage: currentPage?.intValue,
                maxPage: maxPage?.intValue,
                messageActionsByIndex: messageActionsByIndex,
                topicTitle: topicTitle,
                hasPoll: hasPoll,
                pollIsNewVote: pollIsNewVote,
                pollData: pollData,
                searchInputData: searchInputData
            )))
        }
        function(controller, selector, url as NSString, anchor as NSString?, block)
    }

    private func extractMessageActionsByIndex(from controller: NSObject) -> [Int: TopicPageMessageActions] {
        let selector = NSSelectorFromString(LegacyTopicWorkerRuntime.SelectorName.messageActions)
        guard controller.responds(to: selector) else {
            return [:]
        }

        typealias Function = @convention(c) (AnyObject, Selector) -> NSDictionary?
        let implementation = controller.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        guard let rawEntries = function(controller, selector) as? [AnyHashable: Any] else {
            return [:]
        }

        var result: [Int: TopicPageMessageActions] = [:]
        for (rawKey, rawValue) in rawEntries {
            let index: Int
            if let number = rawKey as? NSNumber {
                index = number.intValue
            } else if let string = rawKey as? String, let parsed = Int(string) {
                index = parsed
            } else {
                continue
            }

            guard let entry = rawValue as? [AnyHashable: Any] else {
                continue
            }

            let actions = TopicPageMessageActions(
                quoteURL: urlValue(in: entry, key: MessageActionKey.quoteURL),
                profileURL: urlValue(in: entry, key: MessageActionKey.profileURL),
                privateMessageURL: urlValue(in: entry, key: MessageActionKey.privateMessageURL),
                avatarImagePath: stringValue(in: entry, key: MessageActionKey.avatarImagePath),
                postID: stringValue(in: entry, key: MessageActionKey.postID),
                editURL: urlValue(in: entry, key: MessageActionKey.editURL),
                favoriteURL: urlValue(in: entry, key: MessageActionKey.favoriteURL),
                alertURL: urlValue(in: entry, key: MessageActionKey.alertURL),
                permalinkURL: urlValue(in: entry, key: MessageActionKey.permalinkURL),
                authorName: stringValue(in: entry, key: MessageActionKey.authorName),
                quoteJS: stringValue(in: entry, key: MessageActionKey.quoteJS),
                isOwnMessage: boolValue(in: entry, key: MessageActionKey.isOwnMessage),
                canBeFavorite: boolValue(in: entry, key: MessageActionKey.canBeFavorite),
                isPrivateCategory: boolValue(in: entry, key: MessageActionKey.isPrivateCategory),
                canAQ: boolValue(in: entry, key: MessageActionKey.canAQ),
                canBookmark: boolValue(in: entry, key: MessageActionKey.canBookmark),
                canDelete: boolValue(in: entry, key: MessageActionKey.canDelete),
                topicID: stringValue(in: entry, key: MessageActionKey.topicID),
                topicCategory: stringValue(in: entry, key: MessageActionKey.topicCategory),
                topicTitle: stringValue(in: entry, key: MessageActionKey.topicTitle)
            )

            if actions.quoteURL != nil ||
                actions.profileURL != nil ||
                actions.privateMessageURL != nil ||
                actions.avatarImagePath != nil ||
                actions.postID != nil ||
                actions.editURL != nil ||
                actions.favoriteURL != nil ||
                actions.alertURL != nil ||
                actions.permalinkURL != nil ||
                actions.authorName != nil ||
                actions.quoteJS != nil ||
                actions.isOwnMessage ||
                actions.canBeFavorite ||
                actions.isPrivateCategory ||
                actions.canAQ ||
                actions.canBookmark ||
                actions.canDelete ||
                actions.topicID != nil ||
                actions.topicCategory != nil ||
                actions.topicTitle != nil {
                result[index] = actions
            }
        }

        return result
    }

    private func urlValue(in dictionary: [AnyHashable: Any], key: String) -> URL? {
        guard let rawValue = stringValue(in: dictionary, key: key) else {
            return nil
        }
        return URL(string: rawValue)
    }

    private func stringValue(in dictionary: [AnyHashable: Any], key: String) -> String? {
        guard let rawValue = dictionary[key] as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolValue(in dictionary: [AnyHashable: Any], key: String) -> Bool {
        if let number = dictionary[key] as? NSNumber {
            return number.boolValue
        }
        guard let string = stringValue(in: dictionary, key: key)?.lowercased() else {
            return false
        }
        return string == "1" || string == "true" || string == "yes"
    }
}

struct TopicPageRenderOutput {
    let fileURL: URL?
    let readAccessURL: URL?
}

enum TopicPageRenderingError: LocalizedError {
    case offlineStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .offlineStorageUnavailable:
            return "OfflineStorage is unavailable"
        }
    }
}

protocol TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput
}

struct OfflineStorageTopicPageRenderer: TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput {
        guard let offlineStorage = OfflineStorage.shared() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        guard let cacheDirectoryURL = offlineStorage.cacheURL() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        let fileURL = cacheDirectoryURL
            .appendingPathComponent("topic-\(UUID().uuidString)")
            .appendingPathExtension("htm")
        try html.write(to: fileURL, atomically: false, encoding: .utf8)
        return TopicPageRenderOutput(fileURL: fileURL, readAccessURL: cacheDirectoryURL)
    }
}

enum MessageWebNavigationType {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
    case unknown
}

enum MessageWebInitialScroll: Equatable {
    case top
    case bottom
}

enum MessageWebPopupSource: Equatable {
    case avatar
    case message
}

struct MessageWebPopupPayload: Equatable {
    let source: MessageWebPopupSource
    let messageIndex: Int
    let yOffset: Int
    let xOffset: Int?
}

struct MessageWebSmileyPayload: Equatable {
    let code: String
    let imageURL: String
}

enum MessageWebAction: Equatable {
    case allowNavigation
    case ignore
    case loadPage(Int, MessageWebInitialScroll)
    case refreshCurrentPage
    case showPopupMenu(MessageWebPopupPayload)
    case manageSmileyFavorite(MessageWebSmileyPayload)
    case presentImageViewer(URL)
    case openInternalTopic(URL)
    case openExternalURL(URL)
}

protocol MessageWebActionHandling {
    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction
}

struct MessageWebActionHandler: MessageWebActionHandling {
    private enum Constants {
        static let autoScheme = "oijlkajsdoihjlkjasdoauto"
        static let touchScheme = "oijlkajsdoihjlkjasdotouch"
        static let preloadedScheme = "oijlkajsdoihjlkjasdopreloaded"
        static let loadedScheme = "oijlkajsdoihjlkjasdoloaded"
        static let refreshScheme = "oijlkajsdoihjlkjasdorefresh"
        static let popupAvatarScheme = "oijlkajsdoihjlkjasdopopupavatar"
        static let popupMessageScheme = "oijlkajsdoihjlkjasdopopupmessage"
        static let imageBrowserScheme = "oijlkajsdoihjlkjasdoimbrows"
        static let smileyScheme = "oijlkajsdoihjlkjasdosmiley"
    }

    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction {
        let scheme = (url.scheme ?? "").lowercased()

        if navigationType == .other, url.fragment == "bas" {
            return .ignore
        }

        if scheme == Constants.autoScheme {
            guard let pageAction = autoPagingAction(for: url, currentPage: currentPage, maxPage: maxPage) else {
                return .ignore
            }
            return pageAction
        }

        if scheme == Constants.refreshScheme {
            return .refreshCurrentPage
        }

        if let popupAction = popupAction(for: url, scheme: scheme) {
            return popupAction
        }

        if let imageBrowserAction = imageBrowserAction(for: url, scheme: scheme) {
            return imageBrowserAction
        }

        if let smileyAction = smileyAction(for: url, scheme: scheme) {
            return smileyAction
        }

        if isIgnoredCustomScheme(scheme) {
            return .ignore
        }

        if navigationType == .linkActivated {
            if isForumTopicURL(url) || scheme == "file" {
                return .openInternalTopic(url)
            }
            if scheme == "http" || scheme == "https" {
                return .openExternalURL(url)
            }
        }

        return .allowNavigation
    }

    private func autoPagingAction(for url: URL, currentPage: Int, maxPage: Int) -> MessageWebAction? {
        let boundedMaxPage = max(maxPage, 1)
        let boundedCurrentPage = min(max(currentPage, 1), boundedMaxPage)
        let command = (url.host ?? url.lastPathComponent).lowercased()

        switch command {
        case "begin":
            guard boundedCurrentPage != 1 else { return nil }
            return .loadPage(1, .top)
        case "previous":
            guard boundedCurrentPage > 1 else { return nil }
            return .loadPage(boundedCurrentPage - 1, .bottom)
        case "next":
            guard boundedCurrentPage < boundedMaxPage else { return nil }
            return .loadPage(boundedCurrentPage + 1, .top)
        case "end":
            guard boundedCurrentPage != boundedMaxPage else { return nil }
            return .loadPage(boundedMaxPage, .bottom)
        default:
            return nil
        }
    }

    private func popupAction(for url: URL, scheme: String) -> MessageWebAction? {
        switch scheme {
        case Constants.popupAvatarScheme:
            guard let payload = popupPayload(for: url, source: .avatar) else {
                return .ignore
            }
            return .showPopupMenu(payload)
        case Constants.popupMessageScheme:
            guard let payload = popupPayload(for: url, source: .message) else {
                return .ignore
            }
            return .showPopupMenu(payload)
        default:
            return nil
        }
    }

    private func popupPayload(for url: URL, source: MessageWebPopupSource) -> MessageWebPopupPayload? {
        var values: [Int] = []
        if let host = url.host, let hostValue = Int(host) {
            values.append(hostValue)
        }
        values.append(contentsOf: url.pathComponents.compactMap(Int.init))

        guard let messageIndex = values.last else {
            return nil
        }
        let yOffset = values.dropLast().last ?? 0
        let xOffset = values.count >= 3 ? values.dropLast(2).last : nil
        return MessageWebPopupPayload(
            source: source,
            messageIndex: messageIndex,
            yOffset: yOffset,
            xOffset: xOffset
        )
    }

    private func isIgnoredCustomScheme(_ scheme: String) -> Bool {
        scheme == Constants.touchScheme ||
            scheme == Constants.preloadedScheme ||
            scheme == Constants.loadedScheme
    }

    private func imageBrowserAction(for url: URL, scheme: String) -> MessageWebAction? {
        guard scheme == Constants.imageBrowserScheme else {
            return nil
        }

        guard let imageURL = decodeEmbeddedURL(from: url, expectedScheme: Constants.imageBrowserScheme) else {
            return .ignore
        }

        return .presentImageViewer(imageURL)
    }

    private func smileyAction(for url: URL, scheme: String) -> MessageWebAction? {
        guard scheme == Constants.smileyScheme else {
            return nil
        }

        let prefix = "\(Constants.smileyScheme)://smileycode/"
        let absolute = url.absoluteString
        guard absolute.lowercased().hasPrefix(prefix) else {
            return .ignore
        }

        let remainder = String(absolute.dropFirst(prefix.count))
        guard let separatorIndex = remainder.firstIndex(of: "/") else {
            return .ignore
        }

        let encodedCode = String(remainder[..<separatorIndex])
        let encodedURL = String(remainder[remainder.index(after: separatorIndex)...])

        let decodedCode = (encodedCode.removingPercentEncoding ?? encodedCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedCode.isEmpty else {
            return .ignore
        }

        let normalizedCode = decodedCode.hasPrefix("[:") ? decodedCode : "[:\(decodedCode)]"

        guard let smileyURL = decodeEmbeddedURL(encodedURL) else {
            return .ignore
        }

        return .manageSmileyFavorite(
            MessageWebSmileyPayload(
                code: normalizedCode,
                imageURL: smileyURL.absoluteString
            )
        )
    }

    private func decodeEmbeddedURL(from url: URL, expectedScheme: String) -> URL? {
        let prefix = "\(expectedScheme)://"
        let absolute = url.absoluteString
        guard absolute.lowercased().hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(absolute.dropFirst(prefix.count))
        guard let separatorIndex = remainder.firstIndex(of: "/") else {
            return nil
        }

        let encodedURL = String(remainder[remainder.index(after: separatorIndex)...])
        return decodeEmbeddedURL(encodedURL)
    }

    private func decodeEmbeddedURL(_ encodedURL: String) -> URL? {
        var decoded = encodedURL
        for _ in 0..<2 {
            if let nextDecoded = decoded.removingPercentEncoding, nextDecoded != decoded {
                decoded = nextDecoded
            } else {
                break
            }
        }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func isForumTopicURL(_ url: URL) -> Bool {
        guard (url.host ?? "").lowercased() == "forum.hardware.fr" else {
            return false
        }
        let firstPathComponent = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        return firstPathComponent == "forum2.php" || firstPathComponent == "hfr"
    }
}

struct TopicQuickActionsConfiguration {
    var showOpenFirstPage = true
    var showOpenLastPage = true
    var showOpenLastReply = true
    var showOpenPagePicker = true
    var showCopyLink = true
}

enum TopicOpenContext: Equatable {
    case generic
    case forum(selectedFlag: TopicListFlag)
    case favorites
    case favoritesOnly
    case globalSearch
    case messages
    case privateMessages
}

enum TopicQuickActionPolicy {
    static func defaults(for context: TopicOpenContext) -> TopicQuickActionsConfiguration {
        switch context {
        case .forum:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: true,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        case .favorites:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: true,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        case .favoritesOnly:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: true,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        case .globalSearch:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: true,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        case .messages, .privateMessages:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: false,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        case .generic:
            return TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showOpenLastReply: true,
                showOpenPagePicker: true,
                showCopyLink: true
            )
        }
    }

    static func lastReplyURL(for topic: Topic, context: TopicOpenContext) -> String? {
        switch context {
        case .favorites:
            return nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL)
        case .favoritesOnly, .forum, .globalSearch, .messages, .privateMessages, .generic:
            return nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURL)
        }
    }

    static func copyLink(for topic: Topic) -> String? {
        let rawURL = nonEmptyString(topic.aURLOfFirstPage) ?? nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURLOfLastPost)
        guard let rawURL else { return nil }
        return absoluteForumURLString(from: rawURL)
    }

    private static func absoluteForumURLString(from rawURL: String) -> String {
        guard URL(string: rawURL)?.scheme == nil else { return rawURL }

        let forumBaseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr")!
        if let resolvedURL = URL(string: rawURL, relativeTo: forumBaseURL)?.absoluteURL {
            return resolvedURL.absoluteString
        }
        return rawURL
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct TopicOpenPolicy {
    struct Decision {
        let preferredURL: String?
        let fallbackPage: Int
    }

    static func defaultDecision(for topic: Topic, context: TopicOpenContext) -> Decision {
        let currentPage = max(Int(topic.curTopicPage), 1)
        let maxPage = max(Int(topic.maxTopicPage), 1)

        switch context {
        case .forum(let selectedFlag):
            if topic.isViewedFromForumAtLoad {
                return Decision(
                    preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURL),
                    fallbackPage: maxPage
                )
            }
            if let flaggedURL = nonEmptyString(topic.aURLOfFlag) {
                return Decision(preferredURL: flaggedURL, fallbackPage: currentPage)
            }
            if selectedFlag != .all {
                return Decision(
                    preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL),
                    fallbackPage: maxPage
                )
            }
            return Decision(
                preferredURL: nonEmptyString(topic.aURL),
                fallbackPage: currentPage
            )
        case .favorites:
            if let flaggedURL = nonEmptyString(topic.aURLOfFlag) {
                return Decision(preferredURL: flaggedURL, fallbackPage: currentPage)
            }
            return Decision(
                preferredURL: nonEmptyString(topic.aURL),
                fallbackPage: currentPage
            )
        case .favoritesOnly:
            if topic.isViewed {
                return Decision(
                    preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURL),
                    fallbackPage: maxPage
                )
            }
            if let flaggedURL = nonEmptyString(topic.aURLOfFlag) {
                return Decision(preferredURL: flaggedURL, fallbackPage: currentPage)
            }
            return Decision(
                preferredURL: nonEmptyString(topic.aURL),
                fallbackPage: currentPage
            )
        case .globalSearch:
            let searchMatchURL = TopicPageURLRouting.searchMatchURL(from: topic.sLastSearchPostURL)
            return Decision(
                preferredURL: searchMatchURL ?? nonEmptyString(topic.aURL),
                fallbackPage: max(TopicPageURLRouting.pageNumber(from: searchMatchURL) ?? currentPage, 1)
            )
        case .messages:
            return Decision(
                preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL),
                fallbackPage: maxPage
            )
        case .privateMessages:
            return Decision(
                preferredURL: nonEmptyString(topic.aURLOfFlag) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL),
                fallbackPage: max(TopicPageURLRouting.pageNumber(from: topic.aURLOfFlag) ?? currentPage, 1)
            )
        case .generic:
            return Decision(
                preferredURL: nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage),
                fallbackPage: currentPage
            )
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum TopicPageURLRouting {
    static func searchMatchURL(from urlString: String?) -> String? {
        guard let trimmedURL = nonEmptyString(urlString) else { return nil }
        guard var components = URLComponents(string: trimmedURL) else {
            return searchMatchURLByRegex(from: trimmedURL)
        }

        if let fragment = components.fragment, !fragment.isEmpty {
            return components.string ?? trimmedURL
        }

        if let numReponse = components.queryItems?.first(where: { $0.name == "numreponse" })?.value,
           let postID = normalizedPostAnchorID(from: numReponse) {
            components.fragment = "t\(postID)"
            return components.string ?? trimmedURL
        }

        return trimmedURL
    }

    static func pageNumber(from urlString: String?) -> Int? {
        guard let urlString = nonEmptyString(urlString) else { return nil }

        if
            let components = URLComponents(string: urlString),
            let pageValue = components.queryItems?.first(where: { $0.name == "page" })?.value,
            let page = Int(pageValue),
            page > 0
        {
            print("[TopicPageTrace][TopicPageURLRouting.pageNumber] source=query url=\(urlString) parsedPage=\(page)")
            return page
        }

        let patterns = [
            "page=(\\d+)",
            "_(\\d+)\\.htm"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
            guard
                let match = regex.firstMatch(in: urlString, options: [], range: range),
                match.numberOfRanges >= 2,
                let captureRange = Range(match.range(at: 1), in: urlString),
                let page = Int(urlString[captureRange]),
                page > 0
            else {
                continue
            }
            print("[TopicPageTrace][TopicPageURLRouting.pageNumber] source=regex pattern=\(pattern) url=\(urlString) parsedPage=\(page)")
            return page
        }

        print("[TopicPageTrace][TopicPageURLRouting.pageNumber] source=nil url=\(urlString)")
        return nil
    }

    static func replacingPage(in urlString: String, page: Int) -> String {
        guard let trimmedURL = nonEmptyString(urlString) else { return urlString }

        let fragmentlessURL: String
        if let fragmentIndex = trimmedURL.firstIndex(of: "#") {
            fragmentlessURL = String(trimmedURL[..<fragmentIndex])
        } else {
            fragmentlessURL = trimmedURL
        }

        var updated = fragmentlessURL
        if let range = updated.range(of: "page=\\d+", options: .regularExpression) {
            updated.replaceSubrange(range, with: "page=\(page)")
            return updated
        }
        if let range = updated.range(of: "_\\d+\\.htm", options: .regularExpression) {
            updated.replaceSubrange(range, with: "_\(page).htm")
            return updated
        }
        if var components = URLComponents(string: updated) {
            var queryItems = components.queryItems ?? []
            if let index = queryItems.firstIndex(where: { $0.name == "page" }) {
                queryItems[index].value = "\(page)"
            } else {
                queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
            }
            components.queryItems = queryItems
            components.fragment = nil
            return components.string ?? updated
        }
        return updated
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedPostAnchorID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "0" else { return nil }
        return trimmed
    }

    private static func searchMatchURLByRegex(from urlString: String) -> String {
        if urlString.contains("#") {
            return urlString
        }
        guard
            let regex = try? NSRegularExpression(pattern: "(?:\\?|&)numreponse=(\\d+)", options: [.caseInsensitive]),
            let match = regex.firstMatch(
                in: urlString,
                options: [],
                range: NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
            ),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: urlString),
            let postID = normalizedPostAnchorID(from: String(urlString[captureRange]))
        else {
            return urlString
        }
        return "\(urlString)#t\(postID)"
    }
}

private struct TopicNavigationTarget {
    let topic: Topic
    let page: Int
    let maxPage: Int
    let openedURL: String?
    let initialScroll: WebView.InitialScroll?
}

private struct TopicPagePickerSheetToken: Identifiable {
    let id = UUID()
}

private struct TopicPagePickerQuickButton: View {
    let title: String?
    let systemImage: String?
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.appThemePalette) private var themePalette

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themePalette.actionTintColor)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(themePalette.actionTintColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(Color(uiColor: .systemGray3))
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TopicPagePickerSheet: View {
    let maxPage: Int
    @Binding var pageInput: String
    let onSubmit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmedInput: String {
        pageInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedPage: Int {
        let fallback = min(max(1, Int(trimmedInput) ?? 1), maxPage)
        return min(max(fallback, 1), maxPage)
    }

    private var isInputValid: Bool {
        guard let page = Int(trimmedInput) else { return false }
        return (1...maxPage).contains(page)
    }

    private func setPage(_ page: Int) {
        let clampedPage = min(max(page, 1), maxPage)
        pageInput = "\(clampedPage)"
    }

    private func offsetPage(by delta: Int) {
        setPage(resolvedPage + delta)
    }

    private func submit() {
        onSubmit(resolvedPage)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choisir une page entre 1 et \(maxPage)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TopicPagePickerQuickButton(
                        title: nil,
                        systemImage: "backward.end",
                        accessibilityLabel: "Première page"
                    ) {
                        setPage(1)
                    }

                    TextField("1...\(maxPage)", text: $pageInput)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)

                    TopicPagePickerQuickButton(
                        title: nil,
                        systemImage: "forward.end",
                        accessibilityLabel: "Dernière page"
                    ) {
                        setPage(maxPage)
                    }
                }

                HStack(spacing: 10) {
                    TopicPagePickerQuickButton(
                        title: "-10",
                        systemImage: nil,
                        accessibilityLabel: "Dix pages en moins"
                    ) {
                        offsetPage(by: -10)
                    }
                    TopicPagePickerQuickButton(
                        title: "-1",
                        systemImage: nil,
                        accessibilityLabel: "Une page en moins"
                    ) {
                        offsetPage(by: -1)
                    }
                    TopicPagePickerQuickButton(
                        title: "+1",
                        systemImage: nil,
                        accessibilityLabel: "Une page en plus"
                    ) {
                        offsetPage(by: 1)
                    }
                    TopicPagePickerQuickButton(
                        title: "+10",
                        systemImage: nil,
                        accessibilityLabel: "Dix pages en plus"
                    ) {
                        offsetPage(by: 10)
                    }
                }
            }
            .padding(20)
            .navigationTitle("Page numéro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.bold())
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Fermer")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Valider") {
                        submit()
                    }
                    .disabled(!isInputValid)
                }
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .onAppear {
            if trimmedInput.isEmpty {
                setPage(1)
            }
        }
    }
}

struct MenuActionLabel: View {
    let title: String
    let systemImage: String?
    let assetImage: String?
    let role: ButtonRole?
    let tintColor: Color?
    let iconTintUIColor: UIColor?

    init(
        _ title: String,
        systemImage: String? = nil,
        assetImage: String? = nil,
        role: ButtonRole? = nil,
        tintColor: Color? = nil,
        iconTintUIColor: UIColor? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.assetImage = assetImage
        self.role = role
        self.tintColor = tintColor
        self.iconTintUIColor = iconTintUIColor
    }

    private var foregroundColor: Color {
        if let tintColor { return tintColor }
        return role == .destructive ? Color.red : Color.primary
    }

    private var iconTintColor: UIColor {
        if let iconTintUIColor { return iconTintUIColor }
        return role == .destructive ? UIColor.systemRed : UIColor.label
    }

    private var menuIconImage: UIImage? {
        if let systemImage {
            return UIImage(systemName: systemImage)?
                .withTintColor(iconTintColor, renderingMode: .alwaysOriginal)
        }
        if let assetImage {
            return UIImage(named: assetImage)?
                .withTintColor(iconTintColor, renderingMode: .alwaysOriginal)
        }
        return nil
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(foregroundColor)
        } icon: {
            if let menuIconImage {
                Image(uiImage: menuIconImage)
                    .renderingMode(.original)
            }
        }
    }
}

struct TopicListRowView: View {
    let topic: Topic
    let isVisited: Bool
    var titleFont: Font? = .headline
    var titleBaseSize: CGFloat?
    var titleWeight: Font.Weight = .regular
    var titleOverride: String? = nil
    var titleLeadingBadge: AnyView? = nil
    var showUnreadBadge = false
    var showUnreadBadgeWhenZero = false
    var leadingBottomText: String?
    var trailingBottomText: String?
    var detailText: String?
    var detailContent: AnyView?
    var rowBackgroundTint: Color?
    var contentPadding: EdgeInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    var rowBackgroundOverflow: EdgeInsets = EdgeInsets()
    var leadingAccessory: AnyView?
    var openContext: TopicOpenContext = .generic
    var quickActions: TopicQuickActionsConfiguration?
    var extraContextMenu: (() -> AnyView)?
    var onOpen: ((String?) -> Void)?
    @Environment(\.appThemePalette) private var themePalette
    @AppStorage(AppTextSizeScale.key) private var textSizeScaleRawValue = AppTextSizeScale.standard.rawValue
    @ScaledMetric(relativeTo: .body) private var scaledTitleBaseSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var scaledFooterBaseSize: CGFloat = 13

    @State private var navigateToTarget = false
    @State private var navigationTarget: TopicNavigationTarget?
    @State private var pagePickerSheet: TopicPagePickerSheetToken?
    @State private var pagePickerInput = ""

    private var unreadCount: Int {
        max(Int(topic.maxTopicPage - topic.curTopicPage), 0)
    }

    private var titleText: String {
        titleOverride ?? topic._aTitle ?? "Sans titre"
    }

    private var appTextSizeFactor: CGFloat {
        AppTextSizeScale.value(for: textSizeScaleRawValue).factor
    }

    private var resolvedTitleFont: Font {
        if let titleBaseSize {
            let normalizedBaseSize = scaledTitleBaseSize * (titleBaseSize / 13)
            return .system(size: normalizedBaseSize * appTextSizeFactor, weight: titleWeight)
        }
        return titleFont ?? .headline
    }

    private var resolvedFooterFont: Font {
        .system(size: scaledFooterBaseSize * appTextSizeFactor)
    }

    private var maxTopicPageValue: Int {
        max(Int(topic.maxTopicPage), 1)
    }

    private var currentPageValue: Int {
        max(Int(topic.curTopicPage), 1)
    }

    private var defaultURL: String? {
        nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage)
    }

    private var firstPageURL: String? {
        nonEmptyString(topic.aURLOfFirstPage) ?? nonEmptyString(topic.aURL)
    }

    private var lastPageURL: String? {
        nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURL)
    }

    private var resolvedQuickActions: TopicQuickActionsConfiguration {
        quickActions ?? TopicQuickActionPolicy.defaults(for: openContext)
    }

    private var copyURL: String? {
        TopicQuickActionPolicy.copyLink(for: topic)
    }

    private var searchMatchURL: String? {
        TopicPageURLRouting.searchMatchURL(from: topic.sLastSearchPostURL)
    }

    private var unreadBadgeTextColor: Color {
        themePalette.unreadBadgeTextColor(isVisited: isVisited)
    }

    private var unreadBadgeBackgroundColor: Color {
        themePalette.unreadBadgeBackgroundColor(isVisited: isVisited)
    }

    private var stickySymbolColor: Color {
        themePalette.stickyAccentColor
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func navigationTopic(url: String, page: Int, maxPage: Int) -> Topic {
        let destination = Topic()
        destination._aTitle = topic._aTitle
        destination.aURL = url
        destination.aURLOfFirstPage = topic.aURLOfFirstPage
        destination.aURLOfFlag = topic.aURLOfFlag
        destination.aTypeOfFlag = topic.aTypeOfFlag
        destination.aURLOfLastPost = topic.aURLOfLastPost
        destination.aURLOfLastPage = nonEmptyString(topic.aURLOfLastPage) ?? url
        destination.curTopicPage = Int32(page)
        destination.maxTopicPage = Int32(max(maxPage, page))
        destination.postID = topic.postID
        destination.catID = topic.catID
        destination.aAuthorOrInter = topic.aAuthorOrInter
        destination.aAuthorOfLastPost = topic.aAuthorOfLastPost
        destination.aDateOfLastPost = topic.aDateOfLastPost
        destination.isViewed = topic.isViewed
        destination.isViewedFromForumAtLoad = topic.isViewedFromForumAtLoad
        destination.isLocallyViewedInApp = topic.isLocallyViewedInApp
        destination.isPoll = topic.isPoll
        destination.isClosed = topic.isClosed
        destination.isSticky = topic.isSticky
        destination.isSuperFavorite = topic.isSuperFavorite
        print("[TopicPageTrace][TopicListRowView.navigationTopic] context=\(openContext) title=\(topic._aTitle ?? "") url=\(url) destinationPage=\(page) destinationMax=\(maxPage) sourceCur=\(topic.curTopicPage) sourceMax=\(topic.maxTopicPage) sourceFlag=\(topic.aURLOfFlag ?? "nil") sourceLastPage=\(topic.aURLOfLastPage ?? "nil")")
        return destination
    }

    private func makeNavigationTarget(
        preferredURL: String?,
        fallbackPage: Int? = nil,
        initialScroll: WebView.InitialScroll? = nil
    ) -> TopicNavigationTarget? {
        guard let openedURL = nonEmptyString(preferredURL) ?? defaultURL else {
            return nil
        }

        let resolvedPage = max(TopicPageURLRouting.pageNumber(from: openedURL) ?? fallbackPage ?? currentPageValue, 1)
        let resolvedMaxPage = max(maxTopicPageValue, resolvedPage)
        print("[TopicPageTrace][TopicListRowView.makeNavigationTarget] context=\(openContext) title=\(titleText) openedURL=\(openedURL) fallbackPage=\(String(describing: fallbackPage)) currentPageValue=\(currentPageValue) maxTopicPageValue=\(maxTopicPageValue) resolvedPage=\(resolvedPage) resolvedMax=\(resolvedMaxPage)")
        let destinationTopic = navigationTopic(url: openedURL, page: resolvedPage, maxPage: resolvedMaxPage)

        return TopicNavigationTarget(
            topic: destinationTopic,
            page: resolvedPage,
            maxPage: resolvedMaxPage,
            openedURL: openedURL,
            initialScroll: initialScroll
        )
    }

    private func defaultOpenTarget() -> TopicNavigationTarget? {
        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: openContext)
        print("[TopicPageTrace][TopicListRowView.defaultOpenTarget] context=\(openContext) title=\(titleText) preferredURL=\(decision.preferredURL ?? "nil") fallbackPage=\(String(describing: decision.fallbackPage)) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage) topicURL=\(topic.aURL ?? "nil") flagURL=\(topic.aURLOfFlag ?? "nil") lastPostURL=\(topic.aURLOfLastPost ?? "nil") lastPageURL=\(topic.aURLOfLastPage ?? "nil")")
        return makeNavigationTarget(
            preferredURL: decision.preferredURL ?? defaultURL,
            fallbackPage: decision.fallbackPage
        )
    }

    private func openNavigationTarget(_ target: TopicNavigationTarget?) {
        guard let target else { return }
        navigationTarget = target
        navigateToTarget = true
    }

    private func openDefaultTopic() {
        openNavigationTarget(defaultOpenTarget())
    }

    private func openFirstPageAction() {
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: firstPageURL,
                fallbackPage: 1,
                initialScroll: .top
            )
        )
    }

    private func openLastPageAction() {
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: lastPageURL,
                fallbackPage: maxTopicPageValue,
                initialScroll: .top
            )
        )
    }

    private func openLastReplyAction() {
        let lastReplyURL = TopicQuickActionPolicy.lastReplyURL(for: topic, context: openContext)
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: lastReplyURL,
                fallbackPage: maxTopicPageValue,
                initialScroll: .bottom
            )
        )
    }

    private func openSearchMatchAction() {
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: searchMatchURL,
                fallbackPage: TopicPageURLRouting.pageNumber(from: searchMatchURL) ?? currentPageValue,
                initialScroll: .top
            )
        )
    }

    private func openPagePickerAction() {
        pagePickerInput = "\(currentPageValue)"
        pagePickerSheet = TopicPagePickerSheetToken()
    }

    private func submitPagePicker(pageInput: String? = nil) {
        let trimmed = (pageInput ?? pagePickerInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let requestedPage = Int(trimmed),
            (1...maxTopicPageValue).contains(requestedPage)
        else {
            return
        }

        let baseURL = defaultURL
        let pageURL = baseURL.map { TopicPageURLRouting.replacingPage(in: $0, page: requestedPage) }
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: pageURL,
                fallbackPage: requestedPage,
                initialScroll: .top
            )
        )
    }

    @ViewBuilder
    private var quickActionsMenuContent: some View {
        if openContext == .globalSearch, searchMatchURL != nil {
            Button {
                openSearchMatchAction()
            } label: {
                MenuActionLabel("Dernière correspondance", systemImage: "magnifyingglass")
            }
        }
        if resolvedQuickActions.showOpenFirstPage, firstPageURL != nil {
            Button {
                openFirstPageAction()
            } label: {
                MenuActionLabel("Première page", systemImage: "backward.end")
            }
        }
        if resolvedQuickActions.showOpenLastPage, lastPageURL != nil {
            Button {
                openLastPageAction()
            } label: {
                MenuActionLabel("Dernière page", systemImage: "forward.end")
            }
        }
        if resolvedQuickActions.showOpenLastReply {
            Button {
                openLastReplyAction()
            } label: {
                MenuActionLabel("Dernière réponse", systemImage: "text.append")
            }
        }
        if resolvedQuickActions.showOpenPagePicker {
            Button {
                openPagePickerAction()
            } label: {
                MenuActionLabel("Page numéro...", systemImage: "number")
            }
        }
        if resolvedQuickActions.showCopyLink, let copyURL {
            Button {
                UIPasteboard.general.string = copyURL
            } label: {
                MenuActionLabel("Copier le lien", systemImage: "doc.on.doc")
            }
        }
    }

    var body: some View {
        Button {
            openDefaultTopic()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let leadingAccessory {
                    leadingAccessory
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if topic.isSticky {
                            Image(systemName: "pin.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stickySymbolColor)
                        }
                        if topic.isClosed {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let titleLeadingBadge {
                            titleLeadingBadge
                        }
                        Text(titleText)
                            .font(resolvedTitleFont)
                            .foregroundStyle(isVisited ? .secondary : .primary)
                        Spacer()
                        if showUnreadBadge && (showUnreadBadgeWhenZero || unreadCount > 0) {
                            Text("\(unreadCount)")
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 20)
                                .background(Capsule().fill(unreadBadgeBackgroundColor))
                                .foregroundStyle(unreadBadgeTextColor)
                        }
                    }

                    if let detailContent {
                        detailContent
                    } else if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    if leadingBottomText != nil || trailingBottomText != nil {
                        HStack {
                            if let leadingBottomText {
                                Text(leadingBottomText)
                                    .font(resolvedFooterFont)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let trailingBottomText {
                                Text(trailingBottomText)
                                    .font(resolvedFooterFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(contentPadding)
            .background {
                if let rowBackgroundTint {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(rowBackgroundTint)
                        .padding(.top, -rowBackgroundOverflow.top)
                        .padding(.leading, -rowBackgroundOverflow.leading)
                        .padding(.bottom, -rowBackgroundOverflow.bottom)
                        .padding(.trailing, -rowBackgroundOverflow.trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .contextMenu {
            quickActionsMenuContent
            if let extraContextMenu {
                Divider()
                extraContextMenu()
            }
        }
        .background {
            NavigationLink(
                "",
                isActive: $navigateToTarget
            ) {
                if let navigationTarget {
                    MessagesView(
                        topic: navigationTarget.topic,
                        curPage: navigationTarget.page,
                        maxPage: navigationTarget.maxPage,
                        separatorNewMessages: true,
                        initialLoadScroll: navigationTarget.initialScroll
                    )
                    .onAppear {
                        onOpen?(navigationTarget.openedURL)
                    }
                    .toolbar(.hidden, for: .tabBar)
                } else {
                    EmptyView()
                }
            }
            .hidden()
            .allowsHitTesting(false)
        }
        .sheet(item: $pagePickerSheet) { _ in
            TopicPagePickerSheet(
                maxPage: maxTopicPageValue,
                pageInput: $pagePickerInput
            ) { selectedPage in
                submitPagePicker(pageInput: "\(selectedPage)")
            }
        }
    }
}
