//
//  FocusKeyApp.swift
//  FocusKey
//
//

import SwiftUI

@main
struct FocusKeyApp: App {
    @StateObject private var model = FocusModel()
    @StateObject private var nfc = NFCScanner()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
                .environmentObject(nfc)
        }
    }
}

private struct RootTabView: View {
    @EnvironmentObject private var model: FocusModel
    @EnvironmentObject private var nfc: NFCScanner
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("Bloqueo", systemImage: "lock.shield") }
                .tag(0)
            ScheduleView()
                .tabItem { Label("Horarios", systemImage: "clock") }
                .tag(1)
            LimitsView()
                .tabItem { Label("Límites", systemImage: "hourglass") }
                .tag(2)
            StatsView()
                .tabItem { Label("Estadísticas", systemImage: "chart.bar.fill") }
                .tag(3)
        }
        .onAppear {
            nfc.onValidTag = { model.handleNFC() }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active else { return }
            model.refreshFromStorage()
            // Opened from the "Usar llave" widget, control or shortcut.
            if FocusStore.consumeNFCScanRequest() {
                tab = 0
                nfc.start()
            }
        }
    }
}
