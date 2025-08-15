//
//  AppDelegate.swift
//  SuperHFRplus
//
//  Created by FLK on 06/11/2017.
//

import UIKit

@UIApplicationMain

class AppDelegate: HFRplusAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("application didFinishLaunchingWithOptions")
        return super.legacy_application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

