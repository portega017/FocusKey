//
//  FocusKeyApp.swift
//  FocusKey
//
//  Created by pibol on 14/10/2026.
//

import SwiftUI

@main
struct FocusKeyApp: App {
    @StateObject private var model = FocusModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
        }
    }
}

private struct RootTabView: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Bloqueo", systemImage: "lock.shield")
                }
            ScheduleView()
                .tabItem {
                    Label("Horario", systemImage: "clock")
                }
        }
        .onAppear {
            model.refreshPersistedState()
            model.syncScheduledMonitoringFromStorage()
        }
        .onChange(of: scenePhase, initial: false) { newPhase, _ in
            if newPhase == .active {
                model.refreshPersistedState()
                model.syncScheduledMonitoringFromStorage()
            }
        }
    }
}