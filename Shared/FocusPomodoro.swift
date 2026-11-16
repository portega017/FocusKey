//
//  FocusPomodoro.swift
//  FocusKey
//
//  Pomodoro: focus blocks with breaks in between. Each focus block is its own DeviceActivity
//  interval (FocusKeyPomodoro_<cycle>), so the monitor locks and unlocks without the app.
//  Breaks are just the gaps between intervals, which is why they can be shorter than the
//  15-minute DeviceActivity minimum while focus blocks can't.
//

import Foundation
import UserNotifications

nonisolated struct PomodoroPlan: Codable, Equatable {
    var profileID: UUID
    var start: Date
    var focusMinutes: Int
    var breakMinutes: Int
    var cycles: Int

    static let focusOptions = [25, 30, 45, 50, 60]
    static let breakOptions = [5, 10, 15, 20]
    static let cycleRange = 2...6

    enum Phase: Equatable {
        /// `cycle` is zero-based.
        case focus(cycle: Int, start: Date, end: Date)
        case rest(cycle: Int, start: Date, end: Date)
        case finished
    }

    /// Focus block `cycle` (zero-based).
    func block(_ cycle: Int) -> DateInterval {
        let offset = TimeInterval(cycle * (focusMinutes + breakMinutes) * 60)
        return DateInterval(start: start.addingTimeInterval(offset), duration: TimeInterval(focusMinutes * 60))
    }

    /// End of the last focus block: there is no break after it.
    var end: Date { block(cycles - 1).end }

    func phase(at date: Date) -> Phase {
        guard date >= start else { return .rest(cycle: -1, start: date, end: start) }
        for cycle in 0..<cycles {
            let focus = block(cycle)
            if date < focus.end { return .focus(cycle: cycle, start: focus.start, end: focus.end) }
            if cycle < cycles - 1 {
                let next = block(cycle + 1).start
                if date < next { return .rest(cycle: cycle, start: focus.end, end: next) }
            }
        }
        return .finished
    }

    func isFinished(at date: Date) -> Bool { phase(at: date) == .finished }

    /// Focus time over the whole plan, for summaries.
    var totalFocusMinutes: Int { focusMinutes * cycles }

    /// The same plan with the current break cut short: the next block starts at `date` and every
    /// later block moves earlier by the same amount. Nil when not in a break.
    func skippingBreak(at date: Date) -> PomodoroPlan? {
        guard case let .rest(cycle, _, end) = phase(at: date), cycle >= 0, end > date else { return nil }
        var plan = self
        plan.start = start.addingTimeInterval(-end.timeIntervalSince(date))
        return plan
    }
}

// MARK: - Notifications

/// Local notifications for every phase change, scheduled up front so they arrive even if the app
/// isn't running (opening one refreshes the Live Activity). Used by the app and by intents.
nonisolated enum PomodoroNotifications {
    static func schedule(_ plan: PomodoroPlan) {
        cancel()
        Task {
            // Requests added before permission is granted are dropped.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            add(plan)
        }
    }

    static func cancel() {
        let cycles = 0..<PomodoroPlan.cycleRange.upperBound
        let ids = cycles.map { "pomodoro-rest-\($0)" } + cycles.map { "pomodoro-focus-\($0)" } + ["pomodoro-done"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func add(_ plan: PomodoroPlan) {
        let center = UNUserNotificationCenter.current()
        let profileName = FocusStore.profile(plan.profileID)?.displayName ?? ""

        func add(_ id: String, at date: Date, title: String, body: String) {
            let delay = date.timeIntervalSinceNow
            guard delay > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        for cycle in 0..<plan.cycles {
            let block = plan.block(cycle)
            if cycle < plan.cycles - 1 {
                let next = plan.block(cycle + 1)
                add("pomodoro-rest-\(cycle)", at: block.end,
                    title: String(localized: "Descanso"),
                    body: String(localized: "Tus apps están libres \(UsageLimit.formatted(minutes: plan.breakMinutes)). El ciclo \(cycle + 2) de \(plan.cycles) empieza a las \(next.start.formatted(date: .omitted, time: .shortened))."))
                add("pomodoro-focus-\(cycle + 1)", at: next.start,
                    title: String(localized: "Vuelve a concentrarte"),
                    body: String(localized: "Ciclo \(cycle + 2) de \(plan.cycles): «\(profileName)» bloqueado hasta las \(next.end.formatted(date: .omitted, time: .shortened))."))
            } else {
                add("pomodoro-done", at: block.end,
                    title: String(localized: "Pomodoro completado"),
                    body: String(localized: "\(UsageLimit.formatted(minutes: plan.totalFocusMinutes)) de concentración. ¡Bien hecho!"))
            }
        }
    }
}
