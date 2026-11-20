import Foundation

extension ReaderWebController {
    /// Opens the viewer on the pictures of `urls` the policy lets the reader show now (see `ImageGallery.build`); the page's
    /// list is a claim, so a neighbour the user never allowed and a blocked address stay out. Nothing is answered to the page.
    func openViewer(urls: [String], index: Int, linked: URL? = nil, token: Int) -> Any? {
        if let gallery = ImageGallery.build(
            sources: urls, selected: index, consented: consented, autoLoadsThirdParty: autoLoadsThirdPartyImages(), linked: linked
        ) {
            events.image(gallery.images, gallery.index, token)
        }
        return nil
    }

    /// A tap on a loaded picture, with the link around it when there is one (#912): a link to an image opens that image in the
    /// viewer; a link to anything else goes to the app (`events.pictureLink`), which asks before leaving. Nothing is answered.
    func pictureTapped(urls: [String], index: Int, link: String?, token: Int) -> Any? {
        let shown = urls.indices.contains(index) ? urls[index] : nil
        switch ReaderPictureTap.decide(
            shown: shown, link: link, consented: consented, autoLoadsThirdParty: autoLoadsThirdPartyImages()
        ) {
        case .viewer: return openViewer(urls: urls, index: index, token: token)
        case .linkedImage(let target): return openViewer(urls: urls, index: index, linked: target, token: token)
        case .link(let url): events.pictureLink(url)
        }
        return nil
    }

    /// One decision per image `src`, in order; a third-party image tapped in this document loads (the page asks again after a
    /// reload, #1188).
    func decisions(for urls: [String?]) -> [String] {
        let auto = autoLoadsThirdPartyImages()
        return urls.prefix(Self.maximumImages).map { value -> String in
            guard let text = value, let url = URL(string: text) else { return ImageDecision.block.rawValue }
            return ImageDecision(origin: ImagePolicy.classify(url), autoLoadsThirdParty: auto, tapped: consented.contains(text)).rawValue
        }
    }
}
