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
/// in the bottom inset and the page's last lines stay above them; at full height the bar covers the page, whose insets then
/// stay as they last were instead of growing to the whole viewport (WebKit would get an empty unobscured area).
struct ReaderUnderBars<Content: View>: View {
    @ViewBuilder let content: (EdgeInsets) -> Content
    @Environment(\.dockedComposer) private var docked
    /// The insets before a full-height composer covered the page.
    @State private var kept: EdgeInsets?

    var body: some View {
        GeometryReader { proxy in
            content(Self.insets(proxy.safeAreaInsets, docked: docked, kept: kept))
                .ignoresSafeArea(edges: .vertical)
                .onChange(of: proxy.safeAreaInsets, initial: true) { _, insets in
                    if docked != .full { kept = insets }
                }
        }
        .ignoresSafeArea(Self.ignored(docked: docked))
    }

    /// Bars and banners only, unless a docked composer sits on the keyboard: another keyboard (the "Aller à la page" prompt, a
    /// composer sheet) must not move the page's insets.
    static func ignored(docked: DockedComposer?) -> SafeAreaRegions {
        docked == .partial ? [] : .keyboard
    }

    /// The insets handed to the page: the safe area's, or under a full-height docked composer the ones kept from before.
    static func insets(_ measured: EdgeInsets, docked: DockedComposer?, kept: EdgeInsets?) -> EdgeInsets {
        docked == .full ? kept ?? measured : measured
    }
}
