import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Port of HFRswift/Swift/MessagesView.swift (`FullScreenPhotoViewer` `:5643`, `ZoomableRemoteAnimatedImageView` `:5790`) and
// Classes/SimplePhotoViewController.m @ 2440d79. Differences: GAP-057 / FEAT-014: swipe between the page's images, a visible close
// button (reachable on iPad), share, save and copy link in one menu; no drag-to-dismiss (a full-screen cover has none): Fermer closes.
/// The full-screen image viewer: a pager of zoomable images over black, with a toolbar for close, share, save and copy link.
struct ImageViewerView: View {
    @Bindable var model: ImageViewerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $model.index) {
                ForEach(model.images.indices, id: \.self) { position in
                    page(position).tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(model.positionText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { actionsMenu }
            }
            .overlay(alignment: .bottom) { banner }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.prefetch() }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private func page(_ position: Int) -> some View {
        switch model.states[position] {
        case .loaded(let image):
            ZoomableImage(data: image.data).ignoresSafeArea(edges: .bottom)
        case .failed:
            VStack(spacing: 12) {
                ContentUnavailableView("Impossible de charger la photo", systemImage: "exclamationmark.triangle")
                Button("Réessayer") { model.retry(position) }.buttonStyle(.borderedProminent)
            }
        case .idle, .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionsMenu: some View {
        Menu {
            if let image = model.currentImage {
                // The downloaded bytes, never the address: the system would fetch an address itself (previews, redirects)
                // outside policy C.
                ShareLink(item: SharedImage(image), preview: SharePreview("Image")) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
                Button { Task { await model.saveToPhotos() } } label: {
                    Label("Enregistrer dans Photos", systemImage: "square.and.arrow.down")
                }
            }
            Button { model.copyLink() } label: { Label("Copier le lien", systemImage: "doc.on.doc") }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("Actions de l'image")
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let text = model.feedback {
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .task(id: model.feedbackID) {
                    AccessibilityNotification.Announcement(text).post()
                    try? await Task.sleep(for: .seconds(2.5))
                    model.dismissFeedback()
                }
        }
    }
}

/// The image bytes handed to the share sheet, under their concrete type (an abstract `public.image` is refused by some targets).
private struct SharedImage: Transferable {
    let data: Data
    let type: UTType

    init(_ image: ViewerImage) {
        data = image.data
        type = UTType(mimeType: image.mimeType) ?? .image
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }.exportingCondition { $0.type.conforms(to: .png) }
        DataRepresentation(exportedContentType: .jpeg) { $0.data }.exportingCondition { $0.type.conforms(to: .jpeg) }
        DataRepresentation(exportedContentType: .gif) { $0.data }.exportingCondition { $0.type.conforms(to: .gif) }
        DataRepresentation(exportedContentType: .webP) { $0.data }.exportingCondition { $0.type.conforms(to: .webP) }
        DataRepresentation(exportedContentType: .heic) { $0.data }.exportingCondition { $0.type.conforms(to: .heic) }
        DataRepresentation(exportedContentType: .image) { $0.data }
    }
}

/// A zoomable, pannable image: pinch and double tap, centred when smaller than the screen (legacy: a `UIScrollView`
/// with a 7.5x maximum, `ZoomingImageContainerView`).
private struct ZoomableImage: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> ZoomScrollView { ZoomScrollView() }

    func updateUIView(_ view: ZoomScrollView, context: Context) { view.show(data) }
}

/// The scroll view behind `ZoomableImage`: the image view is sized to the image's aspect ratio and centred with insets, so
/// the letterbox bars neither zoom nor pan.
private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var shownData: Data?
    private var laidOutSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 7.5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleToFill
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Image"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ data: Data) {
        guard data.count != shownData?.count || data != shownData else { return }
        shownData = data
        imageView.image = ViewerImageCheck.displayImage(data)
        zoomScale = 1
        laidOutSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new size (rotation, split view) starts again from the fitted image.
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: fittedSize())
            contentSize = imageView.frame.size
            centre()
            // At zoom 1 the only valid offset is the one that shows the insets: without it a wide picture sits at the top.
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        } else {
            centre()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

    /// The image scaled to fit the bounds.
    private func fittedSize() -> CGSize {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds.size
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Centres what is smaller than the screen on each axis.
    private func centre() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        guard zoomScale == 1 else { return setZoomScale(1, animated: true) }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: imageView.bounds.width / 3, height: imageView.bounds.height / 3)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
