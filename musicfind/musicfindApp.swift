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
            MinimalBootView()
                .onAppear { print("[BOOT] WindowGroup appeared") }
        }
        .onChange(of: scenePhase) { phase in
            print("[BOOT] scenePhase:", String(describing: phase))
        }
    }
}

private struct MinimalBootView: View {
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Boot OK")
                    .font(.largeTitle).bold()
                    .foregroundStyle(.white)
                Text("如果你能看到这一页，说明窗口正常。点击下方按钮打开主界面。")
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button {
                    showContent = true
                    print("[BOOT] Open ContentView tapped")
                } label: {
                    Label("打开主界面", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.red)
            }
            .padding()
        }
        .sheet(isPresented: $showContent) {
            ContentView()
        }
        .onAppear { print("[BOOT] MinimalBootView appeared") }
    }
}
