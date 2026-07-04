//
//  musicfindApp.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI
import UIKit
import Combine

@main
struct musicfindApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chargingSleepGuard = ChargingSleepGuard()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded {
                                chargingSleepGuard.registerInteraction()
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { _ in
                                chargingSleepGuard.registerInteraction()
                            }
                    )

                if chargingSleepGuard.isSleepCoverVisible {
                    ChargingSleepCover {
                        chargingSleepGuard.dismissSleepCover()
                    }
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
                .onAppear { print("[BOOT] WindowGroup appeared") }
        }
        .onChange(of: scenePhase) { phase in
            print("[BOOT] scenePhase:", String(describing: phase))
            chargingSleepGuard.updateScenePhase(phase)
        }
    }
}

@MainActor
private final class ChargingSleepGuard: NSObject, ObservableObject {
    @Published var isSleepCoverVisible = false

    private var scenePhase: ScenePhase = .inactive
    private var sleepTask: Task<Void, Never>?
    private var lastInteraction = Date()
    private let sleepDelay: Duration = .seconds(60)

    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        sleepTask?.cancel()
    }

    func updateScenePhase(_ phase: ScenePhase) {
        scenePhase = phase
        if phase == .active {
            registerInteraction()
        } else {
            sleepTask?.cancel()
            isSleepCoverVisible = false
        }
    }

    func registerInteraction() {
        lastInteraction = Date()
        if isSleepCoverVisible {
            isSleepCoverVisible = false
        }
        scheduleIfNeeded()
    }

    func dismissSleepCover() {
        registerInteraction()
    }

    @objc private func batteryStateDidChange() {
        scheduleIfNeeded()
    }

    private func scheduleIfNeeded() {
        sleepTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false

        guard scenePhase == .active, isCharging else {
            isSleepCoverVisible = false
            return
        }

        let scheduledAt = lastInteraction
        sleepTask = Task { @MainActor in
            try? await Task.sleep(for: sleepDelay)
            guard !Task.isCancelled else { return }
            guard scenePhase == .active, isCharging, lastInteraction == scheduledAt else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isSleepCoverVisible = true
            }
        }
    }

    private var isCharging: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full:
            return true
        case .unplugged, .unknown:
            return false
        @unknown default:
            return false
        }
    }
}

private struct ChargingSleepCover: View {
    let onWake: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("充电保护中")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))

                Text("轻触继续")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.14))
            }
            .padding(.top, 120)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onWake()
        }
    }
}
