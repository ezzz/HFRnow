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
        // Under a docked composer (#853) a drag down on the page pulls the keyboard down with the finger, as in Messages.
        controller.dismissesKeyboardInteractively = context.environment.dockedComposer != nil
        controller.obscuredInsets = UIEdgeInsets(top: obscured.top, left: 0, bottom: obscured.bottom, right: 0)
        controller.show(document)
        controller.apply(scrollRequest)
    }
}

/// Runs the page under the bars (HIG Layout, LOT-186) and hands `content` what they cover. The insets are read where the safe
/// area still applies: read below `ignoresSafeArea`, a `GeometryReader` reports zero, so the web view got no top or bottom
/// inset and the first and last lines of a page stayed under the bars (issues #852, #641).
///
/// Under the reader's docked composer (#853, `dockedComposer`): at partial height the bar sits on the keyboard, so both count
/// in the bottom inset and the page's last lines stay above them. When the bar covers the page (full height, or no page left
/// above it whatever the composer reported yet) the page gets the insets it had before any composer docked, instead of the
/// whole viewport (WebKit would get an empty unobscured area). Order-free: the kept insets are only ever taken with no docked
/// composer, so a first full-height pass before the composer reports its height cannot be kept.
struct ReaderUnderBars<Content: View>: View {
    @ViewBuilder let content: (EdgeInsets) -> Content
    @Environment(\.dockedComposer) private var docked
    /// The insets with no docked composer.
    @State private var kept: EdgeInsets?

    var body: some View {
        GeometryReader { proxy in
            content(Self.insets(proxy.safeAreaInsets, visibleHeight: proxy.size.height, docked: docked, kept: kept))
                .ignoresSafeArea(edges: .vertical)
                .onChange(of: proxy.safeAreaInsets, initial: true) { _, insets in
                    if docked == nil { kept = insets }
                }
                .onChange(of: docked) { _, docked in
                    if docked == nil { kept = proxy.safeAreaInsets }
                }
        }
        .ignoresSafeArea(Self.ignored(docked: docked))
    }

    /// Bars and banners only, unless a docked composer sits on the keyboard: another keyboard (the "Aller à la page" prompt, a
    /// composer sheet) must not move the page's insets.
    static func ignored(docked: DockedComposer?) -> SafeAreaRegions {
        docked == .partial ? [] : .keyboard
    }

    /// Below this, the page above a docked composer is covered: one line of text does not fit.
    static var minimumVisibleHeight: CGFloat { 44 }

    /// The insets handed to the page: the safe area's, or, when a docked composer covers the page, the ones kept with no docked
    /// composer (without any, the bars' top and no bottom inset).
    static func insets(_ measured: EdgeInsets, visibleHeight: CGFloat, docked: DockedComposer?, kept: EdgeInsets?) -> EdgeInsets {
        guard let docked, docked == .full || visibleHeight < minimumVisibleHeight else { return measured }
        return kept ?? EdgeInsets(top: measured.top, leading: measured.leading, bottom: 0, trailing: measured.trailing)
    }
}
