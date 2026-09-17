//
//  musicfindApp.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI

@main
struct musicfindApp: App {
#if DEBUG
    init() {
        if ProcessInfo.processInfo.arguments.contains("--duo-home") {
            UserDefaults.standard.set(true, forKey: "duoOuterLayoutEnabled")
        }
    }
#endif
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--flex-preview") {
                FlexPlayerPreview()
            } else {
                ContentView()
            }
#else
            ContentView()
#endif
        }
    }
}
