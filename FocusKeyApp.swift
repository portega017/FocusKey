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
    /// Debug builds accept `-FocusKeyTab <0-3>` to open a tab directly (for screenshots).
    static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "FocusKeyTab")
        #else
        return 0
        #endif
    }

    @EnvironmentObject private var model: FocusModel
    @EnvironmentObject private var nfc: NFCScanner
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = RootTabView.initialTab
    @State private var toast: String?
    @AppStorage(OnboardingView.doneKey) private var onboardingDone = false
    @State private var showingOnboarding = false

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
            // Strict mode: confirm weakening changes with the tag. The delay lets a closing
            // sheet go away before the NFC reader appears.
            model.requestKey = { message, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    nfc.start(message: message, then: action)
                }
            }
            // Existing users who already picked apps don't need the walkthrough.
            if !onboardingDone {
                if model.activeProfile?.isEmpty == false {
                    onboardingDone = true
                } else {
                    showingOnboarding = true
                }
            }
        }
        .tint(.accentColor)
        .overlay(alignment: .top) {
            if let toast {
                Toast(message: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.toast = nil } }
            }
        }
        .onChange(of: model.statusID) {
            withAnimation(.smooth) { toast = model.status }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.smooth) { toast = nil }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView()
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
