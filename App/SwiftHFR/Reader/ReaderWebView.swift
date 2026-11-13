import SwiftUI
import WebKit

// Moved out of TopicReaderView.swift, which reached SwiftLint's `file_length` with issue #750.
/// Hosts the controller's web view and hands it the model's document, scroll requests and what the bars cover of it.
struct ReaderWebView: UIViewRepresentable {
    let controller: ReaderWebController
    let document: ReaderDocument?
    let scrollRequest: ScrollRequest?
    /// The bars and banners over the page (top and bottom only: the page keeps the horizontal safe area).
    var obscured = EdgeInsets()

    func makeUIView(context: Context) -> WKWebView { controller.webView }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.textScale = context.environment.textScale
        controller.theme = context.environment.themeAppearance
        controller.obscuredInsets = UIEdgeInsets(top: obscured.top, left: 0, bottom: obscured.bottom, right: 0)
        controller.show(document)
        controller.apply(scrollRequest)
    }
}

/// Runs the page under the bars (HIG Layout, LOT-186) and hands `content` what they cover. The insets are read where the safe
/// area still applies: read below `ignoresSafeArea`, a `GeometryReader` reports zero, so the web view got no top or bottom
/// inset and the first and last lines of a page stayed under the bars (issues #852, #641).
struct ReaderUnderBars<Content: View>: View {
    @ViewBuilder let content: (EdgeInsets) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.safeAreaInsets).ignoresSafeArea(edges: .vertical)
        }
        // Bars and banners only: the keyboard (an open reply composer) must not move the page's insets, as before.
        .ignoresSafeArea(.keyboard)
    }
}
