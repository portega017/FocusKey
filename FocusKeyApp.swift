//
//  FocusKeyApp.swift
//  FocusKey
//
//  Created by pibol on 14/10/2026.
//
import SwiftUI
import UserNotifications

// MARK: - Notification Delegate to bridge UNNotification to local NotificationCenter
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == "LockScheduleNotification" {
            // Post a local notification that FocusModel is listening for
            NotificationCenter.default.post(name: Notification.Name("LockScheduleNotification"), object: nil)
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

@main
struct FocusKeyApp: App {
    @StateObject private var model = FocusModel()
    private let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
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
            .environmentObject(model)
            .onAppear {
                UNUserNotificationCenter.current().delegate = notificationDelegate
            }
        }
    }
}
