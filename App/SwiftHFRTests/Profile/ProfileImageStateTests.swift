import Foundation
import Testing
@testable import SwiftHFR

/// LOT-116: what a profile image keeps when a reload restarts its load task.
struct ProfileImageStateTests {
    private let avatar = URL(string: "https://forum-images.hardware.fr/avatar-a.png")!
    private let other = URL(string: "https://forum-images.hardware.fr/avatar-b.png")!

    /// An image that loaded is kept when the reload's attempt fails or is cancelled, and is not downloaded again.
    @Test func anImageThatLoadedIsKeptWhenAReloadFails() {
        var state = ProfileImageState<String>()
        let needs1 = state.begin(url: avatar)
        #expect(needs1)
        state.finish(url: avatar, loaded: "image", cancelled: false)
        #expect(state.image == "image")

        let needs2 = state.begin(url: avatar)
        #expect(!needs2)
        #expect(state.image == "image")
        state.finish(url: avatar, loaded: nil, cancelled: false)
        state.finish(url: avatar, loaded: "late", cancelled: true)
        #expect(state.image == "image")
    }

    /// An image that failed is attempted again by the next task; a cancelled result is dropped.
    @Test func aFailedImageIsRetried() {
        var state = ProfileImageState<String>()
        let needs3 = state.begin(url: avatar)
        #expect(needs3)
        state.finish(url: avatar, loaded: nil, cancelled: false)
        #expect(state.image == nil)
        let needs4 = state.begin(url: avatar)
        #expect(needs4)
        state.finish(url: avatar, loaded: "image", cancelled: true)
        #expect(state.image == nil)
        let needs5 = state.begin(url: avatar)
        #expect(needs5)
        state.finish(url: avatar, loaded: "image", cancelled: false)
        #expect(state.image == "image")
    }

    /// Another URL drops the old image at once; no URL means the placeholder and no download.
    @Test func anotherURLDropsTheOldImage() {
        var state = ProfileImageState<String>()
        _ = state.begin(url: avatar)
        state.finish(url: avatar, loaded: "image", cancelled: false)
        let needs6 = state.begin(url: other)
        #expect(needs6)
        #expect(state.image == nil)
        let needs7 = state.begin(url: nil)
        #expect(!needs7)
    }
}
