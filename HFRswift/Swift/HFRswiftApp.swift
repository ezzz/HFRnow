//
//  HFRswiftApp.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import GiphyUISDK

@main
struct HFRswiftApp: App {

    @UIApplicationDelegateAdaptor(HFRplusAppDelegate.self) var appDelegate

    init() {
        Giphy.configure(apiKey: "nR5R7mvxYnotWSYw9f4ZQuCJgM9LXvRg")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
