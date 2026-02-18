import SwiftUI
import UIKit

struct AnswerView: View {
    let topicURL: URL?
    private let replyPostingService: any ReplyPostingService
    private let smileyCatalogLoader: ReplySmileyCatalogLoading
    private let onPostSuccess: ((ReplyPostingResult) -> Void)?

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool
    @FocusState.Binding var isComposerFocused: Bool

    @State private var composerState: ReplyComposerState
    @State private var defaultSmileys: [ReplySmiley] = []
    @State private var favoriteSmileys: [ReplySmiley] = []
    @State private var selectedRangeUTF16: NSRange = NSRange(location: 0, length: 0)

    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastIsSuccess: Bool = true

    init(
        topicURL: URL?,
        replyPostingService: any ReplyPostingService = ForumReplyPostingService(),
        smileyCatalogLoader: ReplySmileyCatalogLoading = BundleReplySmileyCatalogLoader(),
        onPostSuccess: ((ReplyPostingResult) -> Void)? = nil,
        composerDraftText: Binding<String>,
        isComposerPresented: Binding<Bool>,
        isComposerFocused: FocusState<Bool>.Binding
    ) {
        self.topicURL = topicURL
        self.replyPostingService = replyPostingService
        self.smileyCatalogLoader = smileyCatalogLoader
        self.onPostSuccess = onPostSuccess
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._isComposerFocused = isComposerFocused
        self._composerState = State(initialValue: ReplyComposerState(initialMessage: composerDraftText.wrappedValue))
    }

    private var isDefaultSmileyPickerPresented: Binding<Bool> {
        Binding(
            get: { composerState.activePanel == .defaultSmileys },
            set: { isPresented in
                if !isPresented && composerState.activePanel == .defaultSmileys {
                    composerState.activePanel = .none
                }
            }
        )
    }

    private var isFavoriteSmileyPickerPresented: Binding<Bool> {
        Binding(
            get: { composerState.activePanel == .favoriteSmileys },
            set: { isPresented in
                if !isPresented && composerState.activePanel == .favoriteSmileys {
                    composerState.activePanel = .none
                }
            }
        )
    }

    private var isImageInsertionPresented: Binding<Bool> {
        Binding(
            get: { composerState.activePanel == .imageInsertion },
            set: { isPresented in
                if !isPresented && composerState.activePanel == .imageInsertion {
                    composerState.activePanel = .none
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ReplyTextEditor(
                text: $composerState.message,
                selectedRange: $selectedRangeUTF16,
                isFocused: $isComposerFocused
            )
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Button {
                    presentDefaultSmileys()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 17, weight: .regular))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("Smileys")
                }

                Button {
                    presentFavoriteSmileys()
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 17, weight: .regular))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("Smileys favoris")
                }
                .disabled(favoriteSmileys.isEmpty)

                Button {
                    presentImageInsertion()
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 17, weight: .regular))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("Insérer image")
                }

                Spacer()
                Button {
                    Task { await postMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(composerState.canSend ? Color.accentColor : Color.gray.opacity(0.2))
                        .foregroundColor(composerState.canSend ? .white : .secondary)
                        .clipShape(Capsule())
                        .accessibilityLabel("Send")
                }
                .disabled(!composerState.canSend)
                .padding()
            }
        }
        .navigationTitle("Reply")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: isDefaultSmileyPickerPresented) {
            SmileyPickerView(title: "Smileys", smileys: defaultSmileys) { selectedSmiley in
                insertSmileyCode(selectedSmiley.code)
                composerState.activePanel = .none
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: isFavoriteSmileyPickerPresented) {
            SmileyPickerView(title: "Smileys favoris", smileys: favoriteSmileys) { selectedSmiley in
                insertSmileyCode(selectedSmiley.code)
                composerState.activePanel = .none
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: isImageInsertionPresented) {
            ReplyImageInsertionView { imageURL in
                insertImageMarkup(imageURL)
                composerState.activePanel = .none
            }
            .presentationDetents([.medium])
        }
        .overlay(alignment: .top) {
            if showToast {
                ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
        .onAppear {
            composerState.message = composerDraftText
            if defaultSmileys.isEmpty {
                defaultSmileys = smileyCatalogLoader.loadDefaultSmileys()
            }
            favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()
            selectedRangeUTF16 = NSRange(location: composerState.message.utf16.count, length: 0)
            DispatchQueue.main.async {
                isComposerFocused = true
            }
        }
        .onChange(of: composerState.message) { _, newValue in
            composerDraftText = newValue
        }
    }

    private func presentDefaultSmileys() {
        if defaultSmileys.isEmpty {
            defaultSmileys = smileyCatalogLoader.loadDefaultSmileys()
        }
        composerState.activePanel = .defaultSmileys
    }

    private func presentFavoriteSmileys() {
        favoriteSmileys = smileyCatalogLoader.loadFavoriteSmileys()
        composerState.activePanel = .favoriteSmileys
    }

    private func presentImageInsertion() {
        composerState.activePanel = .imageInsertion
    }

    private func insertSmileyCode(_ smileyCode: String) {
        // Legacy composer inserts spaces around smiley codes.
        let snippet = " \(smileyCode) "
        let insertion = ReplyTextInsertionEngine.insert(
            snippet,
            into: composerState.message,
            selectedUTF16Range: selectedRangeUTF16
        )
        composerState.message = insertion.text
        selectedRangeUTF16 = NSRange(location: insertion.cursorLocationUTF16, length: 0)
        isComposerFocused = true
    }

    private func insertImageMarkup(_ imageURL: String) {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snippet = "[img]\(trimmed)[/img]"
        let insertion = ReplyTextInsertionEngine.insert(
            snippet,
            into: composerState.message,
            selectedUTF16Range: selectedRangeUTF16
        )
        composerState.message = insertion.text
        selectedRangeUTF16 = NSRange(location: insertion.cursorLocationUTF16, length: 0)
        isComposerFocused = true
    }

    private func postMessage() async {
        guard composerState.beginPosting() else { return }
        defer { composerState.endPosting() }

        guard let topicURL else {
            await presentToast(success: false, text: "URL manquante")
            return
        }

        do {
            let result = try await replyPostingService.postReply(message: composerState.message, topicURL: topicURL)
            await MainActor.run {
                onPostSuccess?(result)
            }
            await presentToast(success: true, text: "Hooray")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                composerState.resetAfterSuccessfulPost()
                composerDraftText = ""
                isComposerPresented = false
                isComposerFocused = false
            }
        } catch let error as ReplyPostingError {
            await presentToast(success: false, text: error.localizedDescription)
        } catch {
            await presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
    }

    @MainActor private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation {
            showToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

private struct SmileyPickerView: View {
    let title: String
    let smileys: [ReplySmiley]
    let onSelect: (ReplySmiley) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(smileys) { smiley in
                        Button {
                            onSelect(smiley)
                            dismiss()
                        } label: {
                            SmileyGridCell(smiley: smiley)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SmileyGridCell: View {
    let smiley: ReplySmiley

    var body: some View {
        VStack(spacing: 4) {
            SmileyThumbnailView(smiley: smiley)
                .frame(width: 56, height: 34, alignment: .center)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 6))

            Text(smiley.code)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct SmileyThumbnailView: UIViewRepresentable {
    let smiley: ReplySmiley

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .center
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.update(uiView, with: smiley)
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        coordinator.cancelPendingWork()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private static let bundledImageCache = NSCache<NSString, UIImage>()
        private static let remoteImageCache = NSCache<NSString, UIImage>()
        private var currentSmileyID: String?
        private var loadTask: Task<Void, Never>?

        func update(_ imageView: UIImageView, with smiley: ReplySmiley) {
            guard currentSmileyID != smiley.id else { return }
            currentSmileyID = smiley.id
            loadTask?.cancel()

            imageView.image = nil

            switch smiley.imageSource {
            case .bundledGIF(let filename):
                imageView.image = loadBundledGIF(named: filename)
            case .remote(let url):
                let cacheKey = url.absoluteString as NSString
                if let cached = Self.remoteImageCache.object(forKey: cacheKey) {
                    imageView.image = cached
                    return
                }

                let smileyID = smiley.id
                loadTask = Task { [weak imageView] in
                    guard let image = await self.loadRemoteGIF(from: url) else { return }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.currentSmileyID == smileyID else { return }
                        imageView?.image = image
                    }
                }
            case .none:
                imageView.image = nil
            }
        }

        func cancelPendingWork() {
            loadTask?.cancel()
            loadTask = nil
        }

        private func loadBundledGIF(named filename: String) -> UIImage? {
            let key = filename as NSString
            if let cached = Self.bundledImageCache.object(forKey: key) {
                return cached
            }

            let nsFilename = filename as NSString
            let baseName = nsFilename.deletingPathExtension
            let fileExtension = nsFilename.pathExtension.isEmpty ? "gif" : nsFilename.pathExtension

            let bundle = Bundle.main
            let directPath = bundle.path(forResource: baseName, ofType: fileExtension)
            let nestedPath = bundle.path(
                forResource: baseName,
                ofType: fileExtension,
                inDirectory: "Assets/HFR/Smilies"
            )
            guard let path = directPath ?? nestedPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = decodeGIFImage(from: data) else {
                return nil
            }

            Self.bundledImageCache.setObject(image, forKey: key)
            return image
        }

        private func loadRemoteGIF(from url: URL) async -> UIImage? {
            let cacheKey = url.absoluteString as NSString
            if let cached = Self.remoteImageCache.object(forKey: cacheKey) {
                return cached
            }

            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = decodeGIFImage(from: data) else {
                return nil
            }

            Self.remoteImageCache.setObject(image, forKey: cacheKey)
            return image
        }

        private func decodeGIFImage(from data: Data) -> UIImage? {
            let selector = NSSelectorFromString("sd_imageWithGIFData:")
            let imageClass: AnyObject = UIImage.self
            if imageClass.responds(to: selector),
               let unmanaged = imageClass.perform(selector, with: data),
               let image = unmanaged.takeUnretainedValue() as? UIImage {
                return image
            }
            return UIImage(data: data)
        }
    }
}

private struct ReplyImageInsertionView: View {
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var imageURL = ""

    private var canInsert: Bool {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL image") {
                    TextField("https://...", text: $imageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Insérer image")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Insérer") {
                        onInsert(imageURL)
                        dismiss()
                    }
                    .disabled(!canInsert)
                }
            }
        }
    }
}

private struct ReplyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var isFocused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.keyboardDismissMode = .interactive
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        let boundedSelection = clampedRange(selectedRange, textUTF16Count: uiView.text.utf16.count)
        if uiView.selectedRange != boundedSelection {
            uiView.selectedRange = boundedSelection
        }

        if isFocused.wrappedValue {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func clampedRange(_ range: NSRange, textUTF16Count: Int) -> NSRange {
        let maxLocation = max(min(range.location, textUTF16Count), 0)
        let maxLength = max(min(range.length, textUTF16Count - maxLocation), 0)
        return NSRange(location: maxLocation, length: maxLength)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReplyTextEditor

        init(_ parent: ReplyTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused.wrappedValue {
                parent.isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused.wrappedValue {
                parent.isFocused.wrappedValue = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if !NSEqualRanges(parent.selectedRange, textView.selectedRange) {
                parent.selectedRange = textView.selectedRange
            }
        }
    }
}

private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

private struct AnswerViewPreviewWrapper: View {
    @State private var draft: String = ""
    @State private var presented: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            AnswerView(
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1#t100")!,
                composerDraftText: $draft,
                isComposerPresented: $presented,
                isComposerFocused: $focused
            )
        }
    }
}

#Preview {
    AnswerViewPreviewWrapper()
}
