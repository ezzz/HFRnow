//
//  AppSettingsView.swift
//  HFRswift
//
//  Native SwiftUI settings scaffold (phase S0)
//

import SwiftUI

struct AppSettingsView: View {
    @AppStorage("settings_enable_compact_topic_rows")
    private var enableCompactTopicRows = false

    @AppStorage("settings_enable_experimental_web_router")
    private var enableExperimentalWebRouter = false

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Compact topic rows", isOn: $enableCompactTopicRows)
            }

            Section("Experimental") {
                Toggle("Enable experimental web action router", isOn: $enableExperimentalWebRouter)
            }
        }
        .navigationTitle("Réglages")
    }
}

#Preview("Settings - native SwiftUI") {
    NavigationStack {
        AppSettingsView()
    }
}
