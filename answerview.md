# Specs — AnswerView

> Document de référence pour reconstruire `AnswerView.swift` à l'identique à partir de zéro.
> Toutes les dépendances (protocols, modèles, wrappers ObjC) sont décrits ici.

---

## 1. Vue d'ensemble

`AnswerView` est une fenêtre de composition de réponse à un sujet HFR (ou à un MP).
Elle est présentée en sheet ou en navigation stack ; elle peut aussi remplacer complètement la vue courante (cas `.favoriteSmileys`).

### Fichier source unique
`HFRswift/Swift/AnswerView.swift`

### Imports nécessaires
```swift
import SwiftUI
import UIKit
import PhotosUI
```

---

## 2. Modèles et protocols utilisés

Tous définis dans des fichiers séparés ; **ne pas les redéfinir dans AnswerView.swift**.

### 2.1 ReplyComposer.swift

```swift
enum ReplyComposerPanel: String, Equatable, Identifiable {
    case none, defaultSmileys, favoriteSmileys, imageInsertion
    var id: String { rawValue }
}

struct ReplyComposerState: Equatable {
    var message: String
    var isPosting: Bool
    var activePanel: ReplyComposerPanel

    var trimmedMessage: String          // message.trimmingCharacters(in: .whitespacesAndNewlines)
    var canSend: Bool                   // !isPosting && !trimmedMessage.isEmpty
    mutating func beginPosting() -> Bool
    mutating func endPosting()
    mutating func resetAfterSuccessfulPost()
}

// Moteur d'insertion de texte à la position du curseur (UTF-16)
enum ReplyTextInsertionEngine {
    static func insert(_ snippet: String, into text: String, selectedUTF16Range: NSRange?) -> ReplyTextInsertionResult
}
struct ReplyTextInsertionResult: Equatable {
    let text: String
    let cursorLocationUTF16: Int
}
```

### 2.2 ReplyService.swift — posting

```swift
struct ReplyPostingResult { let refreshAnchor: String?; let refreshURL: URL?; let statusMessage: String? }
enum ReplyPostingError: LocalizedError { case emptyMessage, authenticationRequired, replyFormUnavailable, noActiveAccount, invalidResponse, serverError(statusCode:message:), submissionRejected(message:) }
protocol ReplyPostingService {
    func postReply(message: String, topicURL: URL, formOverrides: [String: String]) async throws -> ReplyPostingResult
}
protocol ReplyComposerContextLoading {
    func fetchComposerContext(topicURL: URL) async throws -> ReplyComposerContext
}
protocol ReplyComposerContextPreloading {
    func preloadReplyContext(topicURL: URL) async
}
struct ReplyComposerContext: Equatable { let subject: String?; let recipient: String? }

// Implémentation concrète (par défaut)
final class ForumReplyPostingService: ReplyPostingService, ReplyComposerContextPreloading, ReplyComposerContextLoading
```

### 2.3 ReplyService.swift — image upload / rehost

```swift
protocol ReplyImageUploadService {
    func uploadImage(_ image: UIImage, maxDimension: RehostUploadMaxDimension) async throws -> RehostUploadedImage
}
enum ReplyImageUploadError: LocalizedError, Equatable { case invalidUploadURL, encodingFailed, invalidResponse, ... }

final class Img3ReplyImageUploadService: ReplyImageUploadService  // implémentation par défaut

enum RehostBBCodeMode: Int, CaseIterable, Identifiable, Codable {
    case imageWithLink = 0   // "Image et lien"
    case imageNoLink = 1     // "Image sans lien"
    case linkOnly = 2        // "Lien seul"
}
enum RehostUploadMaxDimension: Int, CaseIterable, Identifiable, Codable {
    case px1200 = 1200, px1000 = 1000, px800 = 800, px600 = 600, px400 = 400
    var title: String { "\(rawValue) px" }
}
enum RehostImageSizeVariant: String, CaseIterable, Identifiable, Codable {
    case full, medium, preview, mini
    // titres : "Maxi", "Medium", "Preview", "Mini"
}
struct RehostPreferences: Equatable, Codable { var bbCodeMode: RehostBBCodeMode; var maxDimension: RehostUploadMaxDimension }
enum RehostPreferencesStore {
    static func load() -> RehostPreferences   // UserDefaults keys: "rehost_use_link", "rehost_resize_before_upload"
    static func save(_ preferences: RehostPreferences)
}
struct RehostUploadedImage: Identifiable, Equatable, Codable {
    let fullWidth: Int?; let fullHeight: Int?
    let fullURL: String; let mediumURL: String?; let previewURL: String?; let miniURL: String?
    let timeStamp: Date
    var id: String { "\(fullURL)|\(timeStamp.timeIntervalSince1970)" }
    var availableVariants: [RehostImageSizeVariant]
    var thumbnailURL: String          // miniURL ?? mediumURL ?? fullURL
    var maxDimensionText: String?     // "max(w,h) px"
    func formattedSnippet(for variant: RehostImageSizeVariant, mode: RehostBBCodeMode) -> String?
    // snippet format : linkOnly → URL brute ; imageNoLink → [img]url[/img]\n ; imageWithLink → [url=fullURL][img]url[/img][/url]\n
}
enum RehostUploadHistoryStore {
    static func load() -> [RehostUploadedImage]   // Documents/rehostImagesSwiftUI.json
    static func save(_ images: [RehostUploadedImage])
}
```

### 2.4 ReplySmileyCatalog.swift

```swift
enum ReplySmileyImageSource: Equatable { case bundledGIF(filename: String); case remote(URL); case none }
struct ReplySmiley: Identifiable, Equatable { let code: String; let imageSource: ReplySmileyImageSource }

protocol ReplySmileyCatalogLoading {
    func loadDefaultSmileys() -> [ReplySmiley]
    func loadFavoriteSmileys() -> [ReplySmiley]
}

// Implémentation concrète (par défaut)
final class BundleReplySmileyCatalogLoader: ReplySmileyCatalogLoading
// loadDefaultSmileys : lit commonsmile.plist (clé "editor": true, "code", "resource")
// loadFavoriteSmileys : appelle ReplySmileyCacheBridge.favoriteSmileyEntries()
```

#### Wrapper ObjC — SmileyCache
```swift
enum ReplySmileyCacheBridge {
    // Lit les favoris forum ET app via l'objet ObjC SmileyCache.shared
    static func favoriteSmileyEntries() -> [[String: Any]]
    // Clés lues : "arrFavoritesSmileysForum", "arrFavoritesSmileysApp"
    // Entrées : ["source": urlString, "code": smileyCode]

    static func updateForumFavorites(_ entries: [[String: String]])
    // Écrit "arrFavoritesSmileysForum" via setValue(_:forKey:) sur SmileyCache.shared
}
// Accès ObjC : NSClassFromString("SmileyCache"), NSSelectorFromString("shared")
```

### 2.5 SmileySearchService.swift

```swift
protocol SmileySearching: Sendable {
    func search(query: String) async throws -> [ReplySmiley]
}

// Implémentation HFR : GET https://forum.hardware.fr/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+mot1+mot2
// Réponse HTML ISO-8859-1 ; parse <img src="…" alt="code"> avec NSRegularExpression
struct HFRSmileySearchService: SmileySearching

// Historique de recherche : persisté en UserDefaults clé "smileySearchHistory_v1"
struct SmileySearchHistoryEntry: Codable, Identifiable { var id: String { text }; let text: String; var count: Int; var lastDate: Date }
enum SmileySearchHistoryStore {
    static func record(query: String, resultCount: Int)          // enregistre si query.count >= 3 && resultCount > 0
    static func recentSuggestions(matching text: String, limit: Int = 5) -> [SmileySearchHistoryEntry]   // triés par date desc
    static func topSuggestions(matching text: String, limit: Int = 10) -> [SmileySearchHistoryEntry]     // triés par count desc
}
```

### 2.6 LiquidGlass.swift — helpers globaux

```swift
extension View {
    // Applique presentationBackground(.thinMaterial) sur iOS 26+
    func presentationGlassBackground() -> some View
}
```

### 2.7 MessagesView.swift — FullScreenPhotoViewer

```swift
struct FullScreenPhotoViewer: View {
    let url: URL
    let presentationID: UUID
}
```

### 2.8 Wrapper ObjC — session cookie (pseudo / hash_check)

Utilisé dans `ForumReplyPostingService` (pas dans AnswerView directement, transparent via le protocole).

---

## 3. AnswerView — structure principale

### 3.1 Signature et propriétés

```swift
struct AnswerView: View {
    // --- Paramètres d'initialisation ---
    let topicURL: URL?
    let title: String                        // défaut: "Répondre"
    let requiresSubject: Bool                // défaut: false (mode MP)
    let initialRecipient: String?            // défaut: nil

    // Services injectables (avec valeurs par défaut)
    private let replyPostingService: any ReplyPostingService        // ForumReplyPostingService()
    private let smileyCatalogLoader: ReplySmileyCatalogLoading      // BundleReplySmileyCatalogLoader()
    private let imageUploadService: any ReplyImageUploadService     // Img3ReplyImageUploadService()
    private let onPostSuccess: ((ReplyPostingResult) -> Void)?

    // Bindings
    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool

    // --- État ---
    @Environment(\.appThemePalette) private var themePalette
    @Environment(\.dismiss) private var dismiss
    @AppStorage("haptics") private var hapticsEnabled = true

    @State private var composerState: ReplyComposerState            // init avec composerDraftText.wrappedValue
    @State private var composerSubject: String                      // init ""
    @State private var composerRecipient: String?                   // init initialRecipient
    @State private var defaultSmileys: [ReplySmiley] = []
    @State private var favoriteSmileys: [ReplySmiley] = []
    @State private var imageUploadPreferences: RehostPreferences    // init RehostPreferencesStore.load()
    @State private var uploadedImages: [RehostUploadedImage]        // init RehostUploadHistoryStore.load()
    @State private var selectedRangeUTF16: NSRange                  // init NSRange(location:0,length:0)
    @State private var isComposerFocused = false
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []
    @State private var pendingHistoryMutationsToSkip = 0

    @State private var showToast = false
    @State private var toastText = ""
    @State private var toastIsSuccess = true
    @State private var isImageUploading = false
    @State private var imageUploadError: String?
    @State private var imageUploadTask: Task<Void, Never>?
    @State private var favoriteSelectionRefocusTask: Task<Void, Never>?
}
```

### 3.2 Routing des panels

```
composerState.activePanel : ReplyComposerPanel
  .none              → composerContent (vue principale)
  .favoriteSmileys   → FavoriteSmileyPickerView (inline Group, PAS de sheet)
  .defaultSmileys    → sheet → SmileyPickerView
  .imageInsertion    → sheet → ReplyImageInsertionView
```

Binding helper `presentedComposerPanel: Binding<ReplyComposerPanel?>` :
- get: retourne nil si `.none` ou `.favoriteSmileys` (ces cas ne passent pas par sheet)
- set: `composerState.activePanel = $0 ?? .none`

### 3.3 body

```swift
var body: some View {
    Group {
        if composerState.activePanel == .favoriteSmileys {
            FavoriteSmileyPickerView(smileys:, onSelect:, onClose:)
        } else {
            composerContent
        }
    }
    .sheet(item: presentedComposerPanel) { panel in
        switch panel {
        case .defaultSmileys:
            SmileyPickerView(title: "Smileys", smileys: defaultSmileys) { smiley in
                insertSmileyCode(smiley.code)
                composerState.activePanel = .none
            }
            .presentationDetents([.large])
        case .imageInsertion:
            ReplyImageInsertionView(
                preferences: $imageUploadPreferences,
                uploadedImages: $uploadedImages,
                isUploading: $isImageUploading,
                uploadError: $imageUploadError,
                onPickImage: startImageUpload
            ) { snippet in
                insertSnippet(snippet)
                composerState.activePanel = .none
            }
            .presentationDetents([.large])
        case .favoriteSmileys, .none:
            EmptyView()
        }
    }
    .overlay(alignment: .top) {
        if showToast {
            ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
        }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
    .onAppear { /* voir §3.7 */ }
    .task(id: topicURL?.absoluteString) { await loadComposerContext() }
    .onDisappear { /* annuler tasks, sauvegarder draft */ }
    .onChange(of: imageUploadPreferences) { _, new in RehostPreferencesStore.save(new) }
    .onChange(of: uploadedImages) { _, new in RehostUploadHistoryStore.save(new) }
    .onChange(of: composerState.message) { old, new in /* undo history */ }
    // + listeners keyboard pour debug uniquement (#if DEBUG)
}
```

### 3.4 composerContent

```
VStack(spacing: 0) {
    composerHeader          .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    composerMetadataSection .padding(.horizontal).padding(.top, 8)   [si showsComposerMetadata]
    ReplyTextEditor(...)    .padding(12).composerEditorStyle().padding(.horizontal,16).padding(.top,10)  [maxWidth:∞, maxHeight:∞]
    composerToolbar
}
```

### 3.5 composerHeader

```
ZStack {
    Text(title).font(.headline).lineLimit(1).truncationMode(.tail).padding(.horizontal, 96)

    HStack {
        // Bouton fermer (xmark)
        Button { dismissComposer() } label: {
            Image(systemName: "xmark").font(.system(size:14, weight:.bold)).frame(18×18).padding(8)
        }
        .disabled(composerState.isPosting)
        .composerCloseButtonStyle()

        Spacer()

        // Bouton envoyer (arrow.up ou ProgressView)
        Button { Task { await postMessage() } } label: {
            if composerState.isPosting { ProgressView().controlSize(.small).frame(18×18).padding(8) }
            else { Image(systemName:"arrow.up").font(.system(size:16,weight:.bold)).frame(18×18).padding(8) }
        }
        .disabled(!canSend)
        .composerSendButtonStyle(isEnabled: canSend)
        .accessibilityLabel("Envoyer")
    }
}
.frame(height: 44)
```

### 3.6 composerToolbar

Utilise `ViewThatFits` pour s'adapter à la largeur disponible :
1. Version horizontale : `toolbarContent(spacing: 12)` + padding H16 V12
2. Version verticale (fallback) : `toolbarContent(spacing: 10, vertical: true)` + padding H16 V12

`toolbarContent` enveloppe dans `GlassEffectContainer(spacing:)` sur iOS 26+, rien sinon.
`toolbarStack` : HStack horizontal ou VStack vertical.

**Groupe édition** (gauche en horizontal) — `ComposerToolbarGroup` :
| Icône | Label | Désactivé si |
|---|---|---|
| `xmark.circle` | "Vider le texte" | message vide ou isPosting — `isDestructive: true` |
| `arrow.uturn.backward` | "Annuler" | undoHistory vide ou isPosting |
| `arrow.uturn.forward` | "Rétablir" | redoHistory vide ou isPosting |

**Groupe insertion** (droite en horizontal) — `ComposerToolbarGroup` :
| Icône | Label | Désactivé si |
|---|---|---|
| `face.smiling` | "Smileys" | isPosting |
| `star` | "Smileys favoris" | favoriteSmileys vide ou isPosting |
| `photo` | "Insérer image" | isPosting |

### 3.7 Cycle de vie

**onAppear** :
1. `composerState.message = composerDraftText`
2. Vider undoHistory, redoHistory, pendingHistoryMutationsToSkip = 0
3. Charger defaultSmileys si vide : `smileyCatalogLoader.loadDefaultSmileys()`
4. `favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()`
5. `selectedRangeUTF16 = NSRange(location: message.utf16.count, length: 0)`
6. `DispatchQueue.main.async { isComposerFocused = true }`

**onDisappear** :
1. Annuler imageUploadTask et favoriteSelectionRefocusTask
2. `composerDraftText = composerState.message` (sauvegarde le brouillon)

**loadComposerContext** (task liée à topicURL) :
1. Si le service implémente `ReplyComposerContextLoading` : `fetchComposerContext` → remplir composerSubject (si vide) et composerRecipient (si nil)
2. Sinon si `ReplyComposerContextPreloading` : `preloadReplyContext`
3. Dans tous les cas : `favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()`

### 3.8 Logique undo/redo

- `onChange(of: composerState.message)` : si `pendingHistoryMutationsToSkip > 0`, décrémente et skip ; sinon append old value à undoHistory (max 200), vider redoHistory.
- `performUndo` : pop undoHistory → `pendingHistoryMutationsToSkip += 1`, push current à redoHistory, applique valeur, déplace curseur en fin, remet focus.
- `performRedo` : symétrique.

### 3.9 Envoi du message

```swift
private func postMessage() async {
    guard composerState.beginPosting() else { return }
    defer { composerState.endPosting() }

    // Construire formOverrides : "sujet" si requiresSubject, "dest" si composerRecipient
    // Appeler replyPostingService.postReply(message:topicURL:formOverrides:)
    // Succès : triggerPostHaptic(success:true), toast "Hooray", sleep 800ms,
    //          resetAfterSuccessfulPost, vider historiques, composerDraftText="", composerSubject="",
    //          isComposerFocused=false, dismissComposer()
    // Erreur ReplyPostingError : triggerPostHaptic(false), toast error.localizedDescription
    // Erreur générique : triggerPostHaptic(false), toast "Ooops"
}
```

### 3.10 Haptics

`triggerPostHaptic(success:)` : utilise `UINotificationFeedbackGenerator` (.success/.error) + `UIImpactFeedbackGenerator` (.light/.rigid).
Conditionné par `resolvedHapticsEnabled()` qui lit `UserDefaults["haptics"]` en tolérant Bool, NSNumber, String ("1","true","yes","on","0","false","no","off").

### 3.11 Toast

`presentToast(success:text:)` : affiche `ToastBanner` via `showToast=true` avec animation spring, auto-masque après 1,6 s.

### 3.12 Insertion de contenu

```swift
private func insertSmileyCode(_ smileyCode: String, restoreFocus: Bool = true) {
    // Enveloppe le code : " \(smileyCode) " (espaces autour, convention legacy HFR)
    insertSnippet(" \(smileyCode) ", restoreFocus: restoreFocus)
}

private func insertSnippet(_ snippet: String, restoreFocus: Bool = true) {
    // Utilise ReplyTextInsertionEngine.insert(_:into:selectedUTF16Range:)
    // Met à jour composerState.message, selectedRangeUTF16, isComposerFocused
}
```

### 3.13 Gestion du focus après smiley favori

**handleFavoriteSmileySelection** :
1. Annuler refocus task
2. `composerState.activePanel = .none`
3. Task : sleep 80ms → insérer le smiley (`restoreFocus: false`) → `scheduleFavoriteSelectionRefocus`

**handleFavoriteSmileyClose** :
1. Annuler refocus task
2. `composerState.activePanel = .none`
3. Task : sleep 300ms → `isComposerFocused = true`

**scheduleFavoriteSelectionRefocus** : sleep 900ms → si panel=.none ET !isComposerFocused → `isComposerFocused = true`

Raison : sur iOS, fermer une vue en remplacement (FavoriteSmileyPickerView) perturbe le first responder ; le délai laisse le temps au système de stabiliser avant de rappeler le focus sur le UITextView.

### 3.14 Conditions d'affichage

```swift
private var showsComposerMetadata: Bool { requiresSubject || composerRecipient != nil }
private var canSend: Bool {
    guard composerState.canSend else { return false }
    if requiresSubject { return !composerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return true
}
```

### 3.15 composerMetadataSection

```
VStack(alignment:.leading, spacing:10) {
    // Si composerRecipient != nil :
    VStack(alignment:.leading, spacing:4) {
        Text("Destinataire").font(.caption).foregroundStyle(.secondary)
        Text(composerRecipient).font(.body).foregroundStyle(.primary)
    }
    // Si requiresSubject :
    VStack(alignment:.leading, spacing:4) {
        Text("Sujet").font(.caption).foregroundStyle(.secondary)
        TextField("Sujet du MP", text: $composerSubject)
            .textInputAutocapitalization(.sentences).autocorrectionDisabled()
            .padding(.horizontal, 12).padding(.vertical, 10)
            // iOS 26+ : .glassEffect(in: .rect(cornerRadius:10))
            // iOS <26 : .background(themePalette.editorBackgroundColor).clipShape(.rect(cornerRadius:10))
    }
}
```

---

## 4. Sous-structures privées internes

### 4.1 ComposerToolbarGroup

```swift
private struct ComposerToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content
    // iOS 26+ : HStack(spacing:8) + padding H10 V6 + .glassEffect(.regular, in:.capsule)
    // iOS <26  : HStack(spacing:10) + padding H10 V8 + background(tertiarySystemBackground, in:.capsule)
    //            + overlay Capsule stroke separator 0.7 lineWidth 1
}
```

### 4.2 ComposerToolbarButton

```swift
private struct ComposerToolbarButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isDisabled: Bool         // défaut false
    let isDestructive: Bool      // défaut false → foregroundStyle .red si true, sinon .primary
    let action: () -> Void
    // Image systemName, font .system(17, .medium), frame 18×18, padding 8
    // .composerToolbarButtonStyle(isDisabled:) + .disabled(isDisabled) + .opacity(isDisabled ? 0.4 : 1)
}
```

### 4.3 ComposerSheetCloseHeader

```swift
private struct ComposerSheetCloseHeader: View {
    let title: String
    let onClose: () -> Void
    // ZStack : Text(title) centré (padding H96) + HStack avec bouton xmark à gauche
    // .frame(height:44).padding(.horizontal,16).padding(.top,10)
    // Bouton xmark : font .system(14,.bold), frame 18×18, padding 8, .composerCloseButtonStyle(), accessibilityLabel "Fermer"
}
```

### 4.4 ToastBanner

```swift
private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool
    // HStack(spacing:10) : Image(isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
    //   .foregroundStyle(isSuccess ? .green : .orange)
    // + Text(text).font(.headline).foregroundStyle(.primary)
    // .padding(H:14, V:10).background(.ultraThinMaterial).clipShape(Capsule()).shadow(radius:6, y:3)
}
```

### 4.5 SmileyGridCell

```swift
private struct SmileyGridCell: View {
    let smiley: ReplySmiley
    @Environment(\.appThemePalette) private var themePalette
    // SmileyThumbnailView(smiley:)
    //   .frame(width:70, height:50)                    // taille max image smiley
    //   .frame(maxWidth:∞, minHeight:58)               // cell remplit colonne
    //   .background(themePalette.tertiaryBackgroundColor)
    //   .clipShape(.rect(cornerRadius:8))
    //   .contentShape(Rectangle())
}
```

### 4.6 SmileyThumbnailView (UIViewRepresentable)

Affiche un GIF animé (bundlé ou distant) dans un `UIImageView` (ou `SDAnimatedImageView` si disponible).

```swift
private struct SmileyThumbnailView: UIViewRepresentable {
    let smiley: ReplySmiley

    func makeUIView(context:) -> UIImageView {
        // Tente d'instancier SDAnimatedImageView via NSClassFromString("SDAnimatedImageView")
        // Sinon UIImageView standard
        // .contentMode = .center ; .clipsToBounds = true
    }
    func updateUIView(_ uiView:, context:) { context.coordinator.update(uiView, with: smiley) }
    static func dismantleUIView(_ uiView:, coordinator:) { coordinator.cancelPendingWork() }
}
```

**Coordinator** :
- Cache `NSCache<NSString, UIImage>` statique séparé pour bundled vs remote.
- `update(_:with:)` : ignore si même smiley ID ; annule task précédente.
  - `.bundledGIF(filename)` → `loadBundledGIF(named:)` (cherche dans `Bundle.main` direct et `Assets/HFR/Smilies/`) ; appelle `imageView.startAnimating()`
  - `.remote(url)` → vérifie cache → task async `loadRemoteGIF(from:)` → mise à jour sur MainActor
  - `.none` → image = nil
- `decodeGIFImage(from: Data)` :
  1. Tente `UIImage.sd_animatedGIFWithData:` via `NSSelectorFromString` (ObjC wrapper SDWebImage)
  2. Fallback : `CGImageSourceCreateWithData` multi-frames, `UIImage.animatedImage(with:duration:)`
  - Scale 1.0 pour conserver la taille naturelle des GIF
  - `frameDuration` : lit `kCGImagePropertyGIFUnclampedDelayTime` ou `kCGImagePropertyGIFDelayTime` ; si < 0.011 → 0.1

---

## 5. Panneau smileys par défaut — SmileyPickerView

```swift
private struct SmileyPickerView: View {
    let title: String
    let smileys: [ReplySmiley]
    let onSelect: (ReplySmiley) -> Void

    @Environment(\.dismiss) private var dismiss
    // Grille adaptative : GridItem(.adaptive(minimum:78, maximum:90), spacing:4)

    // body :
    // VStack(spacing:0) {
    //   ComposerSheetCloseHeader(title:) { dismiss() }
    //   ScrollView {
    //     LazyVGrid(columns:, spacing:4) {
    //       ForEach(smileys) { smiley in
    //         Button { onSelect(smiley); dismiss() } label: { SmileyGridCell(smiley:) }
    //         .buttonStyle(.plain).accessibilityLabel(smiley.code)
    //       }
    //     }.padding(8)
    //   }
    // }
    // .presentationGlassBackground()
}
```

---

## 6. Panneau smileys favoris — FavoriteSmileyPickerView

Présenté **en remplacement inline** de la vue principale (pas en sheet). Fond `.thinMaterial`.

### 6.1 Signature

```swift
private struct FavoriteSmileyPickerView: View {
    let smileys: [ReplySmiley]
    let onSelect: (ReplySmiley) -> Void
    let onClose: () -> Void
    private let searchService: any SmileySearching = HFRSmileySearchService()
}
```

### 6.2 DisplayMode

```swift
enum DisplayMode: Equatable {
    case favorites
    case results([ReplySmiley])
    case empty
}
```

### 6.3 État

```swift
@State private var displayMode: DisplayMode = .favorites
@State private var searchText = ""
@State private var isSearching = false
@State private var recentSuggestions: [SmileySearchHistoryEntry] = []
@State private var topSuggestions: [SmileySearchHistoryEntry] = []
@State private var searchTask: Task<Void, Never>?
@FocusState private var isSearchFieldFocused: Bool
```

### 6.4 Computed helpers

```swift
var displayedSmileys: [ReplySmiley]   // results si .results, sinon smileys (favoris)
var isShowingResults: Bool            // false si .favorites
var hasSuggestions: Bool              // !recentSuggestions.isEmpty || !topSuggestions.isEmpty
var canSearch: Bool                   // searchText.trimmed.count >= 3
var showSuggestions: Bool             // hasSuggestions && displayMode == .favorites

// Chips à afficher :
// - si searchText vide : recentSuggestions.prefix(4)
// - sinon : (recentSuggestions + topSuggestions sans doublons).prefix(5)
var suggestionChips: [SmileySearchHistoryEntry]
```

### 6.5 Layout body

```
VStack(spacing:0) {
    ComposerSheetCloseHeader("Smileys favoris") { closePanel() }

    ScrollView {
        if .empty → smileyEmptyState
        else → LazyVGrid (même colonnes que SmileyPickerView) { SmileyGridCell + Button }
              .padding(8)
    }

    // Chips suggestions (visible si showSuggestions && !suggestionChips.isEmpty)
    ScrollView(.horizontal, showsIndicators:false) {
        HStack(spacing:8) {
            ForEach(suggestionChips) { entry in
                Button { isSearchFieldFocused=false; searchText=entry.text; performSearch() } label: {
                    HStack(spacing:4) {
                        Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                        Text(entry.text).font(.subheadline)
                    }
                    .padding(H:12,V:6).smileyChipStyle()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal,12).padding(.vertical,8)
    }

    Divider()

    searchBarRow.padding(.horizontal,12).padding(.vertical,10)
}
.frame(maxWidth:∞, maxHeight:∞)
.background(.thinMaterial)
.onAppear { isSearchFieldFocused=false; refreshSuggestions() }
.onChange(of:searchText) { refreshSuggestions() }
.onDisappear { searchTask?.cancel() }
```

### 6.6 searchBarRow

```
HStack(spacing:8) {
    // Bouton retour (si isShowingResults)
    Button { clearSearch() } label: {
        Image(systemName:"chevron.left").font(.system(15,.semibold)).padding(8)
    }
    .accessibilityLabel("Retour aux favoris").smileySearchButtonStyle()

    // Champ de saisie
    HStack {
        TextField("Rechercher un smiley…", text:$searchText)
            .focused($isSearchFieldFocused).submitLabel(.search)
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .onSubmit { performSearch() }
        if !searchText.isEmpty {
            Button { searchText=""; refreshSuggestions() } label: {
                Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Effacer")
        }
    }
    .padding(H:10, V:9).smileySearchFieldStyle()

    // Bouton search ou spinner
    if isSearching {
        ProgressView().controlSize(.small).frame(36×36)
    } else {
        Button { performSearch() } label: {
            Image(systemName:"magnifyingglass").font(.system(15,.semibold)).padding(8)
        }
        .disabled(!canSearch).opacity(canSearch ? 1 : 0.4)
        .accessibilityLabel("Rechercher").smileySearchButtonStyle()
    }
}
```

### 6.7 Empty state

```
VStack(spacing:16) {
    Image(systemName:"questionmark.bubble").font(.system(44)).foregroundStyle(.secondary)
    Text("Aucun smiley trouvé").font(.headline).foregroundStyle(.secondary)
    Text("Essayez avec un autre mot-clé.").font(.subheadline).foregroundStyle(.tertiary)
    Button("Retour aux favoris", action:clearSearch).font(.subheadline).padding(.top,4)
}
.frame(maxWidth:∞).padding(.top,80).padding(.bottom,20)
```

### 6.8 Logique de recherche

```swift
func performSearch() {
    // query.count < 3 → return
    // isSearchFieldFocused = false
    // annuler searchTask précédente ; isSearching = true
    // searchTask : await searchService.search(query:)
    //   succès → SmileySearchHistoryStore.record(query:resultCount:) → .results ou .empty
    //   erreur → .empty
}
func clearSearch() {
    // isSearchFieldFocused=false; annuler task; isSearching=false; displayMode=.favorites
}
func refreshSuggestions() {
    recentSuggestions = SmileySearchHistoryStore.recentSuggestions(matching: searchText)
    topSuggestions    = SmileySearchHistoryStore.topSuggestions(matching: searchText)
}
```

### 6.9 Gestion du focus avant appel des callbacks

```swift
// performAfterSearchFieldBlur(action:) :
// Si isSearchFieldFocused : mettre à false, yield une fois, puis exécuter action
// Sinon : exécuter action immédiatement

func selectSmiley(_ smiley: ReplySmiley) {
    Task { @MainActor in performAfterSearchFieldBlur { onSelect(smiley) } }
}
func closePanel() {
    Task { @MainActor in performAfterSearchFieldBlur { onClose() } }
}
```

---

## 7. Panneau image — ReplyImageInsertionView

Sheet présentée avec `.presentationDetents([.large])`.

### 7.1 Signature

```swift
private struct ReplyImageInsertionView: View {
    @Binding var preferences: RehostPreferences
    @Binding var uploadedImages: [RehostUploadedImage]
    @Binding var isUploading: Bool
    @Binding var uploadError: String?
    let onPickImage: (UIImage) -> Void
    let onInsertSnippet: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemePalette) private var themePalette
    @State private var manualURL = ""
    @State private var presentedPicker: ReplyPresentedImagePicker?
    @State private var photoViewerDestination: ReplyPhotoViewerDestination?
    @FocusState private var isManualURLFocused: Bool
}
```

### 7.2 Helpers visuels

```swift
var canUseCamera: Bool       { UIImagePickerController.isSourceTypeAvailable(.camera) }
var canInsertManualURL: Bool { trimmed url avec scheme http/https }
var prefersProminentPrimaryButtons: Bool { themePalette.colorScheme == .light }
var secondaryControlTintColor: Color {
    themePalette.colorScheme == .light ? Color(uiColor:.systemGray3) : themePalette.actionTintColor
}
```

### 7.3 Layout body

```
VStack(spacing:0) {
    ComposerSheetCloseHeader("Insérer image") { dismiss() }

    List {
        Section("Upload") {
            // Ligne boutons Photos + Caméra (côte à côte, HStack)
            //   Photos : presentedPicker=.photoLibrary ; .replyTintedActionButtonStyle(useProminent:prefersProminent, tint:actionTint)
            //   Caméra : disabled si !canUseCamera ; présente picker .camera sinon uploadError
            //   Les deux : .disabled(isUploading) ; .controlSize(.large) ; .buttonStyle(.borderless) sur le HStack

            // Picker dimension maximale (segmented)
            //   Text("Dimension maximale").font(.caption).foregroundStyle(.secondary)
            //   Picker selection:$preferences.maxDimension .pickerStyle(.segmented)

            // ProgressView("Upload en cours...") si isUploading
            // Text(uploadError).font(.footnote).foregroundStyle(.red) si uploadError non vide
        }

        Section("Images uploadées") {
            // Picker bbCodeMode (segmented) .tint(secondaryControlTintColor)
            // Si uploadedImages vide : Text("Aucune image uploadée.").foregroundStyle(.secondary)
            // Sinon : ForEach(uploadedImages) { ReplyUploadedImageRow(...) }
            //   .swipeActions(edge:.trailing, allowsFullSwipe:true) { Button(role:.destructive) { removeUploadedImage } }
        }

        Section("URL manuelle") {
            TextField("https://...", text:$manualURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).focused($isManualURLFocused)
            Button("Insérer") { insertManualURL() }
                .replyTintedActionButtonStyle(useProminent:false, tint:secondaryControlTintColor)
                .foregroundStyle(.primary).disabled(!canInsertManualURL)
        }
    }
    .padding(.top, 8)
}
.fullScreenCover(item:$presentedPicker) {
    .photoLibrary → ReplyPhotoLibraryPicker(onCancel:, onPick:).ignoresSafeArea()
    .camera       → ReplyUIKitImagePicker(sourceType:.camera, onCancel:, onPick:).ignoresSafeArea()
}
.fullScreenCover(item:$photoViewerDestination) { FullScreenPhotoViewer(url:, presentationID:) }
.presentationGlassBackground()
```

### 7.4 insertManualURL

Crée un `RehostUploadedImage(fullWidth:nil, fullHeight:nil, fullURL:trimmed, mediumURL:nil, previewURL:nil, miniURL:nil)`, génère le snippet via `formattedSnippet(for:.full, mode:preferences.bbCodeMode)`, appelle `onInsertSnippet` puis `dismiss()`.

### 7.5 previewImage

Parcourt `[image.fullURL, mediumURL, previewURL, miniURL]` dans cet ordre, prend le premier URL valide, assigne `photoViewerDestination`.

---

## 8. ReplyUploadedImageRow

```swift
private struct ReplyUploadedImageRow: View {
    let image: RehostUploadedImage
    let mode: RehostBBCodeMode
    let onPreviewImage: () -> Void
    let onInsertVariant: (RehostImageSizeVariant) -> Void

    // Layout :
    // VStack(alignment:.leading, spacing:8) {
    //   HStack(spacing:10) {
    //     Button(action:onPreviewImage) {                    // Thumbnail 56×56
    //       AsyncImage(url: URL(image.thumbnailURL)) { phase in
    //         .success → image.resizable().scaledToFill()
    //         default  → themePalette.controlBackgroundColor
    //       }
    //       .frame(56×56).clipShape(.rect(cornerRadius:8))
    //     }
    //     .buttonStyle(.plain).accessibilityLabel("Afficher l'image")
    //
    //     VStack(alignment:.leading, spacing:4) {
    //       Text(mode.title).font(.caption).foregroundStyle(.secondary)
    //       Text(image.maxDimensionText ?? "Image").font(.footnote).foregroundStyle(.primary)
    //       Text(image.fullURL).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    //     }
    //   }
    //
    //   HStack(spacing:8) {
    //     ForEach(image.availableVariants) { variant in
    //       Button { onInsertVariant(variant) } label: { Text(variant.title).frame(maxWidth:∞) }
    //       .controlSize(.small)
    //       .replyTintedActionButtonStyle(useProminent:false, tint:secondaryControlTintColor)
    //       .foregroundStyle(.primary)
    //     }
    //   }.padding(.vertical, 2)
    // }
}
```

---

## 9. Pickers image (UIViewRepresentable)

### 9.1 ReplyPhotoLibraryPicker

```swift
private struct ReplyPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void
    // PHPickerConfiguration : filter=.images, selectionLimit=1, photoLibrary=.shared()
    // modalPresentationStyle = .fullScreen
    // Coordinator : PHPickerViewControllerDelegate
    //   didFinishPicking : si résultat absent → dismiss + onCancel
    //   sinon provider.loadObject(ofClass:UIImage.self) → dismiss + onPick sur DispatchQueue.main
}
```

### 9.2 ReplyUIKitImagePicker

```swift
private struct ReplyUIKitImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCancel: () -> Void
    let onPick: (UIImage) -> Void
    // UIImagePickerController : delegate=coordinator, allowsEditing=false, modalPresentationStyle=.fullScreen
    // Coordinator : UINavigationControllerDelegate, UIImagePickerControllerDelegate
    //   didCancel → dismiss + onCancel
    //   didFinish → image = info[.originalImage] → dismiss + onPick (ou onCancel si nil)
}
```

---

## 10. ReplyTextEditor (UIViewRepresentable)

Wrapper UITextView qui gère le texte, le curseur (NSRange UTF-16) et le focus.

```swift
private struct ReplyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    func makeUIView(context:) -> UITextView {
        // delegate = coordinator
        // font = UIFont.preferredFont(forTextStyle:.body)
        // backgroundColor = .clear
        // textContainerInset = .zero ; textContainer.lineFragmentPadding = 0
        // autocapitalizationType = .sentences ; autocorrectionType = .yes
        // keyboardDismissMode = .none
    }

    func updateUIView(_ uiView:, context:) {
        // parent = self
        // uiView.text ← text (si différent)
        // uiView.selectedRange ← clampedRange(selectedRange, ...) (si différent)
        // focus : si isFocused && !isFirstResponder → becomeFirstResponder
        //         si !isFocused && isFirstResponder → resignFirstResponder
    }
}
```

**Coordinator** (UITextViewDelegate) :
- `textViewDidBeginEditing` : `parent.isFocused = true` (si pas déjà)
- `textViewDidEndEditing` : ne change pas isFocused (le blur est piloté par les actions de la vue)
- `textViewDidChange` : `parent.text = textView.text`
- `textViewDidChangeSelection` : `parent.selectedRange = textView.selectedRange`

---

## 11. View modifiers privés

Tous définis en `private extension View` dans AnswerView.swift.

| Modifier | iOS 26+ | iOS <26 |
|---|---|---|
| `composerCloseButtonStyle()` | `.buttonBorderShape(.circle).buttonStyle(.glass)` | `.buttonStyle(.bordered).clipShape(.circle)` |
| `composerSendButtonStyle(isEnabled:)` | Si enabled : `.glassProminent` ; sinon `.glass` (tous deux avec `.buttonBorderShape(.circle)`) | Si enabled : `.borderedProminent` ; sinon `.bordered` |
| `composerToolbarButtonStyle(isDisabled:)` | `.buttonStyle(.plain)` | `.buttonStyle(.plain)` |
| `composerEditorStyle()` | `.glassEffect(in:.rect(cornerRadius:18))` | `.background(secondarySystemBackground, in:.rect(cornerRadius:18))` + overlay stroke separator 0.7 |
| `smileySearchFieldStyle()` | `.glassEffect(in:.rect(cornerRadius:10))` | `.background(secondarySystemBackground, in:.rect(cornerRadius:10))` + overlay stroke separator 0.5 |
| `smileySearchButtonStyle()` | `.buttonBorderShape(.circle).buttonStyle(.glass)` | `.buttonStyle(.bordered).clipShape(.circle)` |
| `smileyChipStyle()` | `.glassEffect(.regular.interactive(), in:.capsule)` | `.background(.thinMaterial, in:.capsule)` + overlay Capsule stroke separator 0.3 |
| `replyTintedActionButtonStyle(useProminent:tint:)` | Si prominent : `.glassProminent` ; sinon `.glass` | Si prominent : `.tint(tint).borderedProminent` ; sinon `.tint(tint).bordered` |

---

## 12. Enums et structs auxiliaires

```swift
private enum ReplyPresentedImagePicker: String, Identifiable { case photoLibrary, camera }
private struct ReplyPhotoViewerDestination: Identifiable { let id = UUID(); let url: URL }
```

---

## 13. Debug helpers (compilés uniquement en DEBUG)

```swift
// Sonde le first responder actuel via sendAction ObjC
private enum ComposerDebugFirstResponderProbe { static weak var current: UIResponder? }
private extension UIResponder {
    @objc func _captureComposerDebugFirstResponder() // appelé via sendAction
}
private func debugComposerEvent(_ message: String)   // print "[AnswerView] ..."
private func debugFavoriteEvent(_ message: String)   // print "[FavoriteSmileyPicker] ..."
```

En release : `debugComposerEvent` et `debugFavoriteEvent` sont des no-ops.

---

## 14. Preview

```swift
private struct AnswerViewPreviewWrapper: View {
    @State private var draft = ""
    @State private var presented = false
    var body: some View {
        NavigationStack {
            AnswerView(
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1#t100")!,
                composerDraftText: $draft,
                isComposerPresented: $presented
            )
        }
    }
}
#Preview { AnswerViewPreviewWrapper() }
```

---

## 15. Points d'attention pour la reconstruction

1. **Focus UITextView** : toute la logique de refocus après interaction avec les panneaux de smileys favoris dépend de délais précis (80ms, 300ms, 900ms). Les modifier casse le comportement.
2. **Panel favoris en Group**, pas en sheet : important car une sheet crée un contexte de présentation distinct qui perturbe le premier répondeur différemment.
3. **`pendingHistoryMutationsToSkip`** : mécanisme qui empêche que les mutations programmatiques (undo/redo, insertions) soient enregistrées dans l'historique undo.
4. **UTF-16 range** : tout le tracking de curseur est en UTF-16 (NSRange) pour rester compatible avec UITextView qui travaille nativement en UTF-16.
5. **Wrappers ObjC à réutiliser à l'identique** :
   - `ReplySmileyCacheBridge` : accès à `SmileyCache.shared` via `NSClassFromString` + `NSSelectorFromString`
   - `SmileyThumbnailView.Coordinator.decodeGIFImage` : priorité à `UIImage.sd_animatedGIFWithData:` via selector
6. **Persistance images uploadées** : fichier JSON dans Documents (`rehostImagesSwiftUI.json`), pas en UserDefaults.
7. **Préférences upload** : UserDefaults clés `"rehost_use_link"` (Int) et `"rehost_resize_before_upload"` (Int).
