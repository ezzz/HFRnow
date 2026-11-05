import Foundation

extension ReaderWebController {
    /// Opens the viewer on the pictures of `urls` the policy lets the reader show now (see `ImageGallery.build`); the page's
    /// list is a claim, so a neighbour the user never allowed and a blocked address stay out. Nothing is answered to the page.
    func openViewer(urls: [String], index: Int, token: Int) -> Any? {
        if let gallery = ImageGallery.build(
            sources: urls, selected: index, consented: consented, autoLoadsThirdParty: autoLoadsThirdPartyImages()
        ) {
            events.image(gallery.images, gallery.index, token)
        }
        return nil
    }

    /// One decision per image `src`, in order.
    func decisions(for urls: [String?]) -> [String] {
        let auto = autoLoadsThirdPartyImages()
        return urls.prefix(Self.maximumImages).map { value -> String in
            guard let text = value, let url = URL(string: text) else { return ImageDecision.block.rawValue }
            return ImageDecision(origin: ImagePolicy.classify(url), autoLoadsThirdParty: auto).rawValue
        }
    }
}
