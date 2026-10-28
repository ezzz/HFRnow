import Foundation
@testable import SwiftHFR
import Testing

/// Policy C of LOT-071 (D-071-1): which image URLs the reader may ever request.
struct ImagePolicyTests {
    /// Every spelling LOT-071 names, and their neighbours: never requested, whatever the setting or a tap.
    @Test(arguments: [
        "http://0xC0.0xA8.1.1/a.png", "http://0300.0250.1.1/a.png", "http://192.168.1/a.png", "http://3232235777/a.png",
        "http://[::ffff:192.168.1.1]/a.png", "http://[::1]/a.png", "http://0.0.0.0/a.png", "http://[::]/a.png",
        "http://192.168.1.1/a.png", "http://10.0.0.1/a.png", "http://172.16.5.4/a.png", "http://172.31.255.255/a.png",
        "http://127.0.0.1/a.png", "http://169.254.169.254/latest/meta-data", "http://100.64.0.1/a.png", "http://0.1.2.3/a.png",
        "http://224.0.0.1/a.png", "http://255.255.255.255/a.png", "http://[fc00::1]/a.png", "http://[fe80::1%25en0]/a.png",
        "http://[2001:db8::1]/a.png", "http://192.168.1.1./a.png", "http://0x7f.1/a.png", "http://017700000001/a.png",
        "http://1.2.3.04/a.png", "http://localhost/a.png", "http://router/a.png", "http://nas.local/a.png",
        "http://printer.home.arpa/a.png", "http://a..b/a.png", "http://%31%39%32.168.1.1/a.png",
        "https://forum.hardware.fr/user/logout.php", "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13",
        "https://hardware.fr/", "ftp://example.com/a.png", "https://user:pass@example.com/a.png"
    ])
    func refusedURLsAreBlocked(_ text: String) {
        let origin = ImagePolicy.classify(url(text))
        guard case .blocked = origin else {
            Issue.record("\(text) gave \(origin)")
            return
        }
        #expect(ImageDecision(origin: origin, autoLoadsThirdParty: true, tapped: true) == .block)
    }

    @Test func blockReasonsNameTheRule() {
        #expect(ImagePolicy.classify(url("http://0xC0.0xA8.1.1/")) == .blocked(.numericHost))
        #expect(ImagePolicy.classify(url("http://192.168.1/")) == .blocked(.numericHost))
        #expect(ImagePolicy.classify(url("http://3232235777/")) == .blocked(.numericHost))
        #expect(ImagePolicy.classify(url("http://192.168.1.1/")) == .blocked(.privateAddress))
        #expect(ImagePolicy.classify(url("http://[::1]/")) == .blocked(.privateAddress))
        #expect(ImagePolicy.classify(url("http://router/")) == .blocked(.localName))
        #expect(ImagePolicy.classify(url("https://forum.hardware.fr/user/logout.php")) == .blocked(.forumNonImage))
    }

    @Test(arguments: [
        "https://forum-images.hardware.fr/icones/smile.gif", "https://forum-images.hardware.fr/images/perso/user13.gif",
        "http://forum-images.hardware.fr/themes_static/images_forum/1/avatar.png", "https://forum.hardware.fr/images/logo.png"
    ])
    func forumImagesAreFirstParty(_ text: String) {
        #expect(ImagePolicy.classify(url(text)) == .forum)
        #expect(ImageDecision(origin: .forum, autoLoadsThirdParty: false) == .load)
    }

    @Test(arguments: [
        "https://i.imgur.com/abc.jpg", "http://www.hostingpics.net/x.png", "https://8.8.8.8/a.png", "https://1e100.net/a.png",
        "https://Example.COM./a.png", "https://rehost.diberie.com/Picture/Get/f/1"
    ])
    func publicHostsAreThirdParty(_ text: String) {
        #expect(ImagePolicy.classify(url(text)) == .thirdParty)
    }

    @Test func thirdPartyImagesWaitForATapUnlessTheModeLoadsThem() {
        #expect(ImageDecision(origin: .thirdParty, autoLoadsThirdParty: false) == .tap)
        #expect(ImageDecision(origin: .thirdParty, autoLoadsThirdParty: false, tapped: true) == .load)
        #expect(ImageDecision(origin: .thirdParty, autoLoadsThirdParty: true) == .load)
    }

    @Test func theImageModeFollowsTheSettingAndTheNetwork() {
        #expect(ImageAutoLoad(setting: nil) == .onWiFi)
        #expect(ImageAutoLoad(setting: .wifiOnly) == .onWiFi)
        #expect(ImageAutoLoad(setting: .never) == .onTap)
        #expect(ImageAutoLoad(setting: .always) == .always)
        #expect(ImageAutoLoad.onWiFi.loadsThirdPartyImages(onWiFi: true))
        #expect(!ImageAutoLoad.onWiFi.loadsThirdPartyImages(onWiFi: false))
        #expect(!ImageAutoLoad.onTap.loadsThirdPartyImages(onWiFi: true))
        #expect(ImageAutoLoad.always.loadsThirdPartyImages(onWiFi: false))
    }
}
