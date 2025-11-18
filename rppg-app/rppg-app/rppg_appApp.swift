//
//  rppg_appApp.swift
//  rppg-app
//
//  Created by Jonathan Kierce on 27/8/2025.
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

@main
struct rppg_appApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "hrvCorrectionEnabled": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#endif
