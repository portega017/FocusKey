//
//  ScheduleView.swift
//  FocusKey
//
//  Created by pibol on 14/10/2026.
//
import SwiftUI
import UserNotifications

// MARK: - Notification Manager Singleton
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}
    
    func scheduleNotification(at date: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        let content = UNMutableNotificationContent()
        content.title = "Bloqueo programado"
        content.body = "Es hora de bloquear las aplicaciones"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "LockScheduleNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["LockScheduleNotification"])
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            } else {
                print("Notification scheduled for \(components)")
            }
        }
    }
    
    func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["LockScheduleNotification"])
    }
}

struct ScheduleView: View {
    @EnvironmentObject var model: FocusModel
    @State private var scheduledTime = Date()
    @State private var isEnabled = false
    private let scheduledTimeKey = "ScheduledLockTime"
    private let scheduleEnabledKey = "ScheduleEnabled"
    
    var body: some View {
        Form {
            Section(header: Text("Programar bloqueo automático")) {
                Toggle("Activar programación", isOn: $isEnabled)
                    .onChange(of: isEnabled, initial: false) { newValue, _ in
                        if newValue {
                            NotificationManager.shared.scheduleNotification(at: scheduledTime)
                        } else {
                            NotificationManager.shared.cancelNotification()
                        }
                        UserDefaults.standard.set(newValue, forKey: scheduleEnabledKey)
                    }
                
                DatePicker(
                    "Hora de bloqueo",
                    selection: $scheduledTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(WheelDatePickerStyle())
                .disabled(!isEnabled)
                
                Button(action: saveSchedule) {
                    Text("Guardar horario")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isEnabled)
                
                if isEnabled {
                    Text("Próximo bloqueo: \(formattedTime(scheduledTime))")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            loadSchedule()
            // Restore toggle state
            isEnabled = UserDefaults.standard.bool(forKey: scheduleEnabledKey)
            if isEnabled {
                NotificationManager.shared.scheduleNotification(at: scheduledTime)
            }
        }
        .navigationTitle("Horario de bloqueo")
    }
    
    private func saveSchedule() {
        // Ensure we store a date for today at the selected time, or tomorrow if time has passed
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
        let now = Date()
        let targetDate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        if let target = targetDate {
            scheduledTime = target
            UserDefaults.standard.set(scheduledTime, forKey: scheduledTimeKey)
            if isEnabled {
                NotificationManager.shared.scheduleNotification(at: scheduledTime)
            }
        }
    }
    
    private func loadSchedule() {
        if let saved = UserDefaults.standard.object(forKey: scheduledTimeKey) as? Date {
            scheduledTime = saved
        } else {
            // Default to 07:00 AM today (or tomorrow if already passed)
            let calendar = Calendar.current
            var components = DateComponents()
            components.hour = 7
            components.minute = 0
            let today = calendar.startOfDay(for: Date())
            if let hour = components.hour, let minute = components.minute,
               let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) {
                scheduledTime = date > Date() ? date : calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleView()
            .environmentObject(FocusModel())
    }
}
