//
//  HFRswiftApp.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import GiphyUISDK
import UIKit

@main
struct HFRswiftApp: App {

    @UIApplicationDelegateAdaptor(HFRplusAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LegacySystemBarAppearance.configureIfNeeded()
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

private enum LegacySystemBarAppearance {
    static func configureIfNeeded() {
        guard #available(iOS 17.0, *) else {
            return
        }
        if #available(iOS 26.0, *) {
            return
        }

        let backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.98)
        let shadowColor = UIColor.separator.withAlphaComponent(0.35)

        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        navigationBarAppearance.backgroundColor = backgroundColor
        navigationBarAppearance.shadowColor = shadowColor

        let navigationBarProxy = UINavigationBar.appearance()
        navigationBarProxy.standardAppearance = navigationBarAppearance
        navigationBarProxy.scrollEdgeAppearance = navigationBarAppearance
        navigationBarProxy.compactAppearance = navigationBarAppearance
        if #available(iOS 15.0, *) {
            navigationBarProxy.compactScrollEdgeAppearance = navigationBarAppearance
        }

        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithOpaqueBackground()
        toolbarAppearance.backgroundColor = backgroundColor
        toolbarAppearance.shadowColor = shadowColor

        let toolbarProxy = UIToolbar.appearance()
        toolbarProxy.standardAppearance = toolbarAppearance
        toolbarProxy.scrollEdgeAppearance = toolbarAppearance
        toolbarProxy.compactAppearance = toolbarAppearance
        if #available(iOS 15.0, *) {
            toolbarProxy.compactScrollEdgeAppearance = toolbarAppearance
        }
    }
}
