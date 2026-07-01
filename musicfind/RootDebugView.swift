//
//  RootDebugView.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI

struct RootDebugView: View {
    @State private var showContent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("App Booted")
                    .font(.title)
                    .bold()
                Text("如果你能看到这一页，说明应用窗口正常。点击下面按钮打开主界面。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    showContent = true
                } label: {
                    Label("打开主界面", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("启动诊断")
        }
        .sheet(isPresented: $showContent) {
            ContentView()
        }
    }
}

#Preview {
    RootDebugView()
}
