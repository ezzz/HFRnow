//
//  HFRswiftApp.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI

@main
struct HFRswiftApp: App {
    
    @UIApplicationDelegateAdaptor(HFRplusAppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
