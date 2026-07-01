//
//  musicfindApp.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI

@main
struct musicfindApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { print("[BOOT] WindowGroup appeared") }
        }
        .onChange(of: scenePhase) { phase in
            print("[BOOT] scenePhase:", String(describing: phase))
        }
    }
}
