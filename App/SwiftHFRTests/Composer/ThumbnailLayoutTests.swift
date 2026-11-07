import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// A 480-point GIF must not impose its size on the sheet (the confirmation's "Insérer" fell below the visible area).
@MainActor
struct ThumbnailLayoutTests {
    private struct Probe: UIViewRepresentable {
        let flexible: Bool

        func makeUIView(context: Context) -> UIImageView {
            let view = UIImageView(image: UIGraphicsImageRenderer(size: CGSize(width: 480, height: 480)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 480, height: 480))
            })
            SmileyThumbnailView.configure(view, contentMode: .scaleAspectFit, flexible: flexible)
            return view
        }

        func updateUIView(_ view: UIImageView, context: Context) {}
    }

    private func fitted(flexible: Bool) -> CGSize {
        let host = UIHostingController(rootView: Probe(flexible: flexible).aspectRatio(1, contentMode: .fit))
        return host.sizeThatFits(in: CGSize(width: 100, height: 10_000))
    }

    @Test func aFlexibleThumbnailTakesWhatTheLayoutProposes() {
        let size = fitted(flexible: true)
        #expect(size.width <= 100 && size.height <= 100, "\(size)")
    }

    @Test func aSmileyKeepsItsIntrinsicSize() {
        #expect(fitted(flexible: false).width > 100)
    }
}
