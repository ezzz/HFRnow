import HFRModels
import HFRStorage
import PhotosUI
import SwiftUI
import UIKit

// Port of HFRswift/Swift/AnswerView.swift (ReplyImageInsertionView :1801-1982, ReplyUploadedImageRow :1984-2046) @ 2440d79 (GAP-091).
// LOT-103 (UX evolution b·needed, GAP-091): removal asks first and says the image stays online (legacy :1909 deleted silently).
// Differences: `PhotosPicker` instead of the `PHPickerViewController` wrapper; no full-screen viewer of an uploaded image; no
// "Preview" rendition (the engine has none); the first-use notice N1 before any upload.
/// The panel "Insérer image": photos or camera, the size and BBCode choices, the uploaded images and a manual link. Thin: every
/// rule is in `ImageUploadModel`.
struct ImageUploadView: View {
    let model: ImageUploadModel
    /// Inserts the snippet in the composer and closes the panel.
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var manualURL = ""

    var body: some View {
        NavigationStack {
            List {
                uploadSection
                historySection
                manualSection
            }
            .navigationTitle("Insérer une image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
            .alert("Hébergeur d'images", isPresented: askingNotice) {
                Button("Annuler", role: .cancel) { model.declineNotice() }
                Button("Continuer") { model.acceptNotice() }
            } message: {
                Text(model.noticeMessage)
            }
            .confirmationDialog(
                "Retirer de l'historique ?", isPresented: askingRemoval, titleVisibility: .visible, presenting: model.pendingRemoval
            ) { image in
                Button("Retirer de l'historique", role: .destructive) { Task { await model.confirmRemoval(image) } }
                Button("Annuler", role: .cancel) {}
            } message: { _ in
                Text(ImageUploadModel.removalMessage)
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(
                    onCancel: { isShowingCamera = false },
                    onPick: { data in
                        isShowingCamera = false
                        Task { await submit(data) }
                    }
                )
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task { await submit(try? await item.loadTransferable(type: Data.self)) }
            }
        }
        .task { await model.load() }
        .presentationDetents([.large])
    }

    private func submit(_ data: Data?) async {
        guard let data else { return model.pickFailed() }
        await model.submit(data)
    }

    private var askingNotice: Binding<Bool> {
        // The alert's buttons decide: SwiftUI also sets this to false on "Continuer", before the accept runs.
        Binding(get: { model.isAskingNotice }, set: { _ in })
    }

    private var askingRemoval: Binding<Bool> {
        // A tap outside the dialog cancels; the confirm button gets the image from `presenting`, not from the cleared state.
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } })
    }

    private var canUseCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private var uploadSection: some View {
        Section("Envoyer") {
            if model.canUpload {
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    Button { isShowingCamera = true } label: {
                        Label("Caméra", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .disabled(!canUseCamera)
                }
                .buttonStyle(.bordered)
                .disabled(model.isUploading)
                Picker("Dimension maximale", selection: Binding(get: { model.maxDimension }, set: { model.maxDimension = $0 })) {
                    ForEach(RehostMaxDimension.allCases, id: \.self) { Text("\($0.rawValue) px").tag($0) }
                }
                .pickerStyle(.menu)
            } else {
                Text("L'envoi d'images n'est pas disponible dans cette version. Vous pouvez insérer un lien.")
                    .foregroundStyle(.secondary)
            }
            if model.isUploading { ProgressView("Envoi en cours…") }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let warning = model.historyWarning {
                Text(warning).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var historySection: some View {
        Section("Images envoyées") {
            Picker("Type de BBCode", selection: Binding(get: { model.linkMode }, set: { model.linkMode = $0 })) {
                Text("Image et lien").tag(RehostLinkMode.imageWithLink)
                Text("Image sans lien").tag(RehostLinkMode.imageNoLink)
                Text("Lien seul").tag(RehostLinkMode.linkOnly)
            }
            .pickerStyle(.segmented)
            if model.history.isEmpty {
                Text("Aucune image envoyée.").foregroundStyle(.secondary)
            }
            ForEach(model.history) { image in
                UploadedImageRow(image: image) { variant in onInsert(model.snippet(for: image, variant: variant)) }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Retirer", systemImage: "trash") { model.requestRemoval(image) }.tint(.red)
                    }
            }
            if let notice = model.removalNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var manualSection: some View {
        Section("Lien manuel") {
            TextField("https://…", text: $manualURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Insérer") {
                if let snippet = model.manualSnippet(for: manualURL) { onInsert(snippet) }
            }
            .disabled(ImageUploadModel.manualURL(manualURL) == nil)
        }
    }
}

extension View {
    /// Presents the image panel as a sheet; `onInsert` gets the snippet and the sheet closes.
    func imageUploadSheet(
        isPresented: Binding<Bool>, model: ImageUploadModel, onDismiss: @escaping () -> Void, onInsert: @escaping (String) -> Void
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ImageUploadView(model: model) { snippet in
                onInsert(snippet)
                isPresented.wrappedValue = false
            }
        }
    }
}

/// One uploaded image: its thumbnail, size and one button per rendition the host returned.
private struct UploadedImageRow: View {
    let image: RehostedImage
    let onInsert: (RehostImageVariant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AsyncImage(url: image.miniURL ?? image.mediumURL ?? image.fullURL) { phase in
                    if let loaded = phase.image { loaded.resizable().scaledToFill() } else { Color.secondary.opacity(0.2) }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let width = image.width, let height = image.height { Text("\(max(width, height)) px").font(.footnote) }
                    Text(image.fullURL.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                ForEach(image.availableVariants, id: \.self) { variant in
                    Button(Self.title(variant)) { onInsert(variant) }.frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private static func title(_ variant: RehostImageVariant) -> String {
        switch variant {
        case .full: "Maxi"
        case .medium: "Medium"
        case .mini: "Mini"
        }
    }
}

// Port of HFRswift/Swift/AnswerView.swift (ReplyUIKitImagePicker :2048-2096) @ 2440d79.
/// The system camera; the photo comes back as JPEG bytes (the preparer applies the orientation and drops the metadata).
private struct CameraPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPick: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCancel: onCancel, onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCancel: () -> Void
        private let onPick: (Data?) -> Void

        init(onCancel: @escaping () -> Void, onPick: @escaping (Data?) -> Void) {
            self.onCancel = onCancel
            self.onPick = onPick
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onPick((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1))
        }
    }
}
