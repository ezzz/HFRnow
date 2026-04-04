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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Giphy.configure(apiKey: "nR5R7mvxYnotWSYw9f4ZQuCJgM9LXvRg")
        MPBackgroundService.shared.registerBGTask()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    await MPBackgroundService.shared.requestNotificationAuthorization()
                }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                MPBackgroundService.shared.scheduleAppRefresh()
            }
        }
    }
}
