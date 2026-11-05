import SwiftUI
import UIKit

// Port of HFRswift/Swift/MessagesView.swift (`FullScreenPhotoViewer` `:5643`, `ZoomableRemoteAnimatedImageView` `:5790`) and
// Classes/SimplePhotoViewController.m @ 2440d79. Differences: GAP-057 / FEAT-014: swipe between the page's images, a visible close
// button (reachable on iPad), share, save and copy link in one menu; no drag-to-dismiss, the sheet's own gesture does it.
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
            if model.currentImage != nil, let link = model.currentLink {
                ShareLink(item: link) { Label("Partager", systemImage: "square.and.arrow.up") }
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
                .task {
                    AccessibilityNotification.Announcement(text).post()
                    try? await Task.sleep(for: .seconds(2.5))
                    model.dismissFeedback()
                }
        }
    }
}

/// A zoomable, pannable image: pinch and double tap, centred when smaller than the screen (legacy: a `UIScrollView`
/// with a 7.5x maximum, `ZoomingImageContainerView`).
private struct ZoomableImage: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> ZoomScrollView { ZoomScrollView() }

    func updateUIView(_ view: ZoomScrollView, context: Context) { view.show(data) }
}

/// The scroll view behind `ZoomableImage`.
private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var shownData: Data?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 7.5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Image"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ data: Data) {
        guard data != shownData else { return }
        shownData = data
        imageView.image = UIImage(data: data)
        zoomScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 { imageView.frame = bounds }
        contentSize = imageView.frame.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        guard zoomScale == 1 else { return setZoomScale(1, animated: true) }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
