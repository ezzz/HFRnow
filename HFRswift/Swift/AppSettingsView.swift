//
//  AppSettingsView.swift
//  HFRswift
//
//  Native SwiftUI settings migrated from InAppSettings legacy flow
//

import SwiftUI
import UIKit

@MainActor
struct AppSettingsView: View {
    private enum Constants {
        static let autoThemeIOS = 3
        static let autoThemeManual = 0
        static let defaultTintHue = 190.0 / 360.0
    }

    private struct IntOption: Identifiable {
        let value: Int
        let title: String
        var id: Int { value }
    }

    private struct StringOption: Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }

    private enum AppIconOption: String, CaseIterable, Identifiable {
        case superblue = "superblue"
        case classic = "classic"
        case classicRed = "classic-red"
        case redface = "redface"
        case redfaceBlue = "redface-blue"
        case beta = "beta"
        case blue = "blue"
        case white = "white"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classic:
                return "Classique Yellow"
            case .classicRed:
                return "Classique Red"
            case .superblue:
                return "Défaut"
            case .redface:
                return "REDFACE"
            case .redfaceBlue:
                return "REDFACE Blue"
            case .beta:
                return "Beta"
            case .blue:
                return "Blue"
            case .white:
                return "White"
            }
        }

        var alternateIconName: String? {
            switch self {
            case .superblue:
                return nil
            case .classic:
                return "Icon-CLASSIC"
            case .classicRed:
                return "Icon-CLASSIC-RED"
            case .redface:
                return "Icon-REDFACE"
            case .redfaceBlue:
                return "Icon-REDFACEBLUE"
            case .beta:
                return "Icon-BETA"
            case .blue:
                return "Icon-BLUE"
            case .white:
                return "Icon-WHITE"
            }
        }
    }

    @AppStorage("vos_sujets") private var favoritesTabBehavior = "0"
    @AppStorage("sujets_avec_cat") private var favoritesSortedByCategories = true
    @AppStorage(AppLayoutCompactMode.key) private var compactModeEnabled = false
    @AppStorage(AppTabBarMinimizeOnScroll.key) private var tabBarMinimizeOnScroll = true
    @AppStorage(AppTextSizeScale.key) private var textSizeScaleRawValue = AppTextSizeScale.standard.rawValue
    @AppStorage("haptics") private var hapticsEnabled = true
    @AppStorage("icon") private var iconValue = AppIconOption.superblue.rawValue

    @AppStorage("auto_theme") private var autoTheme = Constants.autoThemeIOS
    @AppStorage("theme") private var manualTheme = 0
    @AppStorage("theme_style") private var themeStyle = 1

    @AppStorage("blacklist_hide_pseudo") private var hideBlacklistedPseudo = false
    @AppStorage("filter_posts_quotes") private var filterPostsMode = "wl_pseudo"
    @AppStorage("filter_posts_min_quotes") private var filterPostsMinimumQuoteCount = 3
    @AppStorage("size_smileys") private var smileySize = "double"
    @AppStorage("embedded_videos") private var embeddedVideos = "yes"
    @AppStorage("display_sig") private var displaySignatures = "no"

    @AppStorage("mpstorage_active") private var mpStorageActive = false
    @AppStorage("mpstorage_last_rw") private var mpStorageLastAccess = "-"
    @AppStorage("mp_badge_enabled") private var mpBadgeEnabled = true

    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showClearCacheConfirmation = false
    @State private var tintHue = Constants.defaultTintHue
    @State private var tintHueLoaded = false

    private var iconOptions: [AppIconOption] {
        AppIconOption.allCases
    }

    private let favoritesTabOptions = [
        StringOption(value: "0", title: "Drapeaux & Favoris"),
        StringOption(value: "1", title: "Favoris uniquement")
    ]

    private let autoThemeOptions = [
        IntOption(value: Constants.autoThemeIOS, title: "Automatique (iOS)"),
        IntOption(value: Constants.autoThemeManual, title: "Manuel")
    ]

    private let manualThemeOptions = [
        IntOption(value: 0, title: "Clair"),
        IntOption(value: 1, title: "Sombre")
    ]

    private let themeStyleOptions = [
        IntOption(value: 0, title: "Classique"),
        IntOption(value: 1, title: "Moderne")
    ]

    private let smileySizeOptions = [
        StringOption(value: "default", title: "Normale"),
        StringOption(value: "double", title: "Grande")
    ]

    private let embeddedVideoOptions = [
        StringOption(value: "no", title: "Lien"),
        StringOption(value: "yes", title: "Intégré"),
        StringOption(value: "both", title: "Intégré + lien")
    ]

    private let signatureOptions = [
        StringOption(value: "yes", title: "Oui"),
        StringOption(value: "no", title: "Non")
    ]

    private let filterPostsMinimumQuoteOptions = [
        IntOption(value: 3, title: "3"),
        IntOption(value: 4, title: "4"),
        IntOption(value: 5, title: "5"),
        IntOption(value: 7, title: "7"),
        IntOption(value: 10, title: "10")
    ]

    private var filterPostsWhitelistBinding: Binding<Bool> {
        Binding(
            get: { filterPostsMode.contains("wl") },
            set: { filterPostsMode = $0 ? "wl_pseudo" : "pseudo" }
        )
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var hasAlternateIconSupport: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private var isLoggedIn: Bool {
        let pseudo = ObjCLegacyAccountsManager.shared.currentPseudo()
        return !(pseudo?.isEmpty ?? true)
    }

    private func applyThemeConfiguration() {
        let defaults = UserDefaults.standard
        let themeManager = ThemeManager.shared()

        if autoTheme == Constants.autoThemeIOS {
            defaults.set(Constants.autoThemeIOS, forKey: "auto_theme")
            themeManager?.refreshTheme()
            return
        }

        let boundedTheme = manualTheme == 1 ? 1 : 0
        if manualTheme != boundedTheme {
            manualTheme = boundedTheme
        }
        defaults.set(Constants.autoThemeManual, forKey: "auto_theme")
        defaults.set(boundedTheme, forKey: "theme")
        themeManager?.refreshTheme()
    }

    private func applyIconSelection() {
        guard hasAlternateIconSupport else { return }
        let selectedOption = AppIconOption(rawValue: iconValue) ?? .superblue
        UIApplication.shared.setAlternateIconName(selectedOption.alternateIconName) { error in
            guard let error else { return }
            Task { @MainActor in
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func handleMPStorageToggle(_ enabled: Bool) {
        guard enabled else { return }

        guard isLoggedIn else {
            mpStorageActive = false
            errorMessage = "Vous devez être identifié sur le forum pour activer le MP storage."
            showErrorAlert = true
            return
        }

        guard let pseudo = ObjCLegacyAccountsManager.shared.currentPseudo(), !pseudo.isEmpty else {
            mpStorageActive = false
            errorMessage = "Impossible de récupérer le pseudo actif."
            showErrorAlert = true
            return
        }

        let success = ObjCMPStorageBridge.shared.initializeOrResetMP(pseudo: pseudo)
        if !success {
            mpStorageActive = false
            errorMessage = "Échec de l'initialisation du MP storage."
            showErrorAlert = true
        }
    }

    private func reloadMPStorage() {
        guard isLoggedIn else {
            errorMessage = "Connectez-vous pour relancer le MP storage."
            showErrorAlert = true
            return
        }
        guard let pseudo = ObjCLegacyAccountsManager.shared.currentPseudo(), !pseudo.isEmpty else {
            errorMessage = "Impossible de récupérer le pseudo actif."
            showErrorAlert = true
            return
        }
        _ = ObjCMPStorageBridge.shared.initializeOrResetMP(pseudo: pseudo)
    }

    private func clearCaches() {
        if let appDelegate = HFRplusAppDelegate.shared() {
            appDelegate.resetApp()
        }

        let fileManager = FileManager.default
        guard let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let folders = ["ImageCache", "SmileCache"]
        for folder in folders {
            let folderURL = cacheRoot.appendingPathComponent(folder, isDirectory: true)
            try? fileManager.removeItem(at: folderURL)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadTintHueIfNeeded() {
        guard !tintHueLoaded else { return }
        tintHueLoaded = true
        tintHue = resolvedTintHue()
    }

    private func resolvedTintHue() -> Double {
        let currentTintColor =
            ThemeUserColorStore.storedColor(forKey: "theme_day_color_action")
            ?? ThemeUserColorStore.defaultTintColor(forLegacyThemeValue: 0)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard currentTintColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Constants.defaultTintHue
        }
        return Double(hue)
    }

    private func applyTintHue(_ hue: Double) {
        let boundedHue = min(max(hue, 0), 1)
        let dayTint = UIColor(hue: boundedHue, saturation: 0.65, brightness: 1.0, alpha: 1.0)
        let nightTint = UIColor(hue: boundedHue, saturation: 0.70, brightness: 0.95, alpha: 1.0)

        ThemeUserColorStore.storeColor(dayTint, forKey: "theme_day_color_action")
        ThemeUserColorStore.storeColor(nightTint, forKey: "theme_night_color_action")
        ThemeManager.shared()?.refreshTheme()
    }

    private func syncLegacyTextSizeSettings() {
        let scale = AppTextSizeScale.value(for: textSizeScaleRawValue)
        let defaults = UserDefaults.standard
        defaults.set(scale.rawValue, forKey: "size_text_topics")
        defaults.set("sys", forKey: "size_text")
        defaults.set(Int((15 * scale.factor).rounded()), forKey: "size_text_reply")
    }

    private func migrateLegacyTextSizeSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppTextSizeScale.key) == nil else { return }

        let legacyTopicSize = defaults.object(forKey: "size_text_topics") as? Int ?? AppTextSizeScale.standard.rawValue
        let supportedValues = AppTextSizeScale.allCases.map(\.rawValue)
        let closestValue = supportedValues.min { lhs, rhs in
            abs(lhs - legacyTopicSize) < abs(rhs - legacyTopicSize)
        } ?? AppTextSizeScale.standard.rawValue
        textSizeScaleRawValue = closestValue
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("Général") {
            Picker("Favoris", selection: $favoritesTabBehavior) {
                ForEach(favoritesTabOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Toggle("Favoris triés par catégories", isOn: $favoritesSortedByCategories)
            Toggle("Mode compact", isOn: $compactModeEnabled)
            Toggle("Réduire la tab bar au scroll", isOn: $tabBarMinimizeOnScroll)

            Picker("Taille du texte", selection: $textSizeScaleRawValue) {
                ForEach(AppTextSizeScale.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            Toggle("Retours haptiques", isOn: $hapticsEnabled)

            Picker("Icône", selection: $iconValue) {
                ForEach(iconOptions) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .disabled(!hasAlternateIconSupport)
        }
    }

    @ViewBuilder
    private var themeSection: some View {
        Section("Thème") {
            Picker("Changement de thème", selection: $autoTheme) {
                ForEach(autoThemeOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            if autoTheme == Constants.autoThemeManual {
                Picker("Luminosité du thème", selection: $manualTheme) {
                    ForEach(manualThemeOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Teinte d'accent")
                    Spacer()
                    Text(tintHue, format: .number.precision(.fractionLength(2)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $tintHue, in: 0...1, step: 0.001)
                    .tint(Color(hue: tintHue, saturation: 0.65, brightness: 1.0))
            }
        }
    }

    @ViewBuilder
    private var topicsSection: some View {
        Section("Sujets") {
            Picker("Style des messages", selection: $themeStyle) {
                ForEach(themeStyleOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Toggle("Masquer les pseudos blacklistés", isOn: $hideBlacklistedPseudo)

            NavigationLink {
                ProfileFilterListEditorView(kind: .blacklist)
            } label: {
                Label("Liste noire", systemImage: "hand.raised")
            }

            NavigationLink {
                ProfileFilterListEditorView(kind: .whitelist)
            } label: {
                Label("Liste blanche", systemImage: "heart")
            }

            Picker("Taille des smileys", selection: $smileySize) {
                ForEach(smileySizeOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Picker("Afficher les vidéos", selection: $embeddedVideos) {
                ForEach(embeddedVideoOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Picker("Afficher les signatures", selection: $displaySignatures) {
                ForEach(signatureOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }
        }
    }

    @ViewBuilder
    private var filterPostsSection: some View {
        Section("Filtrer les posts") {
            Picker("Minimum de citations", selection: $filterPostsMinimumQuoteCount) {
                ForEach(filterPostsMinimumQuoteOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Toggle("Inclure les pseudos whitelistés", isOn: filterPostsWhitelistBinding)
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications MP") {
            Toggle("Badge messages non lus", isOn: $mpBadgeEnabled)
        }
    }

    @ViewBuilder
    private var mpStorageSection: some View {
        Section("Stockage MP") {
            Toggle("Activer le stockage MP", isOn: $mpStorageActive)
            if mpStorageActive {
                LabeledContent("Dernier accès", value: mpStorageLastAccess)
                Button("Resynchroniser MP storage") {
                    reloadMPStorage()
                }
            }
        }
    }

    @ViewBuilder
    private var maintenanceSection: some View {
        Section("Maintenance") {
            Button("Vider le cache", role: .destructive) {
                showClearCacheConfirmation = true
            }
            Button("Ouvrir les réglages système") {
                openSystemSettings()
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("À propos") {
            LabeledContent("Version", value: appVersion)
        }
    }

    var body: some View {
        Form {
            generalSection
            themeSection
            topicsSection
            filterPostsSection
            notificationsSection
            mpStorageSection
            maintenanceSection
            aboutSection
        }
        .compactListSectionSpacing(compactModeEnabled, spacing: 8, regularSpacing: 14)
        .navigationTitle("Réglages")
        .onAppear {
            loadTintHueIfNeeded()
            applyThemeConfiguration()
            migrateLegacyTextSizeSettingsIfNeeded()
            syncLegacyTextSizeSettings()
        }
        .onChange(of: autoTheme) { _, _ in
            applyThemeConfiguration()
        }
        .onChange(of: manualTheme) { _, _ in
            if autoTheme == Constants.autoThemeManual {
                applyThemeConfiguration()
            }
        }
        .onChange(of: tintHue) { _, newValue in
            applyTintHue(newValue)
        }
        .onChange(of: iconValue) { _, _ in
            applyIconSelection()
        }
        .onChange(of: textSizeScaleRawValue) { _, _ in
            syncLegacyTextSizeSettings()
        }
        .onChange(of: mpStorageActive) { _, newValue in
            handleMPStorageToggle(newValue)
        }
        .alert("Erreur", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Vider le cache ?", isPresented: $showClearCacheConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Vider", role: .destructive) {
                clearCaches()
            }
        } message: {
            Text("Tous les onglets seront réinitialisés.")
        }
    }
}

private enum ProfileFilterListKind {
    case blacklist
    case whitelist

    var title: String {
        switch self {
        case .blacklist:
            return "Liste noire"
        case .whitelist:
            return "Liste blanche"
        }
    }

    var emptyMessage: String {
        switch self {
        case .blacklist:
            return "Aucun pseudo blacklisté."
        case .whitelist:
            return "Aucun pseudo whitelisté."
        }
    }

    var footer: String {
        switch self {
        case .blacklist:
            return "La liste noire est liée au compte actif et reste synchronisée avec le comportement legacy."
        case .whitelist:
            return "La liste blanche est globale et utilisée pour les citations, les messages et le filtre des posts."
        }
    }
}

private struct ProfileFilterListEditorView: View {
    let kind: ProfileFilterListKind

    @State private var profiles: [String] = []
    @State private var newProfile = ""
    @State private var alertMessage: String?

    private var trimmedNewProfile: String {
        newProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddProfile: Bool {
        !trimmedNewProfile.isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Pseudo", text: $newProfile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Ajouter") {
                        addProfile()
                    }
                    .disabled(!canAddProfile)
                }
            }

            Section {
                if profiles.isEmpty {
                    Text(kind.emptyMessage)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles, id: \.self) { profile in
                        Text(profile)
                    }
                    .onDelete(perform: removeProfiles)
                }
            } header: {
                Text(kind.title)
            } footer: {
                Text(kind.footer)
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(profiles.isEmpty)
            }
        }
        .onAppear(perform: reloadProfiles)
        .alert("Erreur", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func reloadProfiles() {
        profiles = loadProfiles().sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func loadProfiles() -> [String] {
        switch kind {
        case .blacklist:
            return ObjCProfileFilterListManager.shared.blacklistProfiles()
        case .whitelist:
            return ObjCProfileFilterListManager.shared.whitelistProfiles()
        }
    }

    private func addProfile() {
        let profile = trimmedNewProfile
        guard !profile.isEmpty else { return }

        switch kind {
        case .blacklist:
            if !ObjCProfileFilterListManager.shared.addToBlacklist(profile) {
                alertMessage = "Impossible d'ajouter ce pseudo à la liste noire."
                return
            }
        case .whitelist:
            if !ObjCProfileFilterListManager.shared.addToWhitelist(profile) {
                alertMessage = "Impossible d'ajouter ce pseudo à la liste blanche."
                return
            }
        }

        newProfile = ""
        reloadProfiles()
    }

    private func removeProfiles(at offsets: IndexSet) {
        for index in offsets {
            guard profiles.indices.contains(index) else { continue }
            let profile = profiles[index]
            switch kind {
            case .blacklist:
                if !ObjCProfileFilterListManager.shared.removeFromBlacklist(profile) {
                    alertMessage = "Impossible de supprimer \(profile) de la liste noire."
                }
            case .whitelist:
                if !ObjCProfileFilterListManager.shared.removeFromWhitelist(profile) {
                    alertMessage = "Impossible de supprimer \(profile) de la liste blanche."
                }
            }
        }
        reloadProfiles()
    }
}

#Preview("Réglages") {
    NavigationStack {
        AppSettingsView()
    }
}
