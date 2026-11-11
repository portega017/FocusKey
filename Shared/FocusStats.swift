//
//  FocusStats.swift
//  FocusKey
//
//  Statistics computed from block records: minutes blocked per day and streak.
//

import Foundation

nonisolated struct FocusStats {
    struct Day: Identifiable {
        var date: Date
        var minutes: Int
        var id: Date { date }
    }

    let week: [Day]
    /// Five full weeks (Monday to Sunday) ending with the current one, for the calendar.
    /// Days after today are included with 0 minutes so the grid stays aligned.
    let calendarDays: [Day]
    let today: Int
    let streak: Int
    let recent: [BlockRecord]

    init(records: [BlockRecord], now: Date = .now, calendar: Calendar = .current) {
        let intervals = Self.merged(records.map { ($0.start, min($0.end ?? now, now)) })
        let todayStart = calendar.startOfDay(for: now)

        func minutes(on dayStart: Date) -> Int {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let seconds = intervals.reduce(0.0) { total, interval in
                let start = max(interval.0, dayStart)
                let end = min(interval.1, dayEnd)
                return total + max(0, end.timeIntervalSince(start))
            }
            return Int(seconds / 60)
        }

        week = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayStart).map { Day(date: $0, minutes: minutes(on: $0)) }
        }
        today = minutes(on: todayStart)

        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let thisWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let firstDay = calendar.date(byAdding: .day, value: -28, to: thisWeek) ?? thisWeek
        calendarDays = (0..<35).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return Day(date: day, minutes: day > now ? 0 : minutes(on: day))
        }

        // Consecutive days with at least one minute blocked; today counts only once it has some.
        var streak = 0
        var day = today > 0 ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while minutes(on: day) > 0, streak < 365 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        self.streak = streak

        recent = Array(records.sorted { $0.start > $1.start }.prefix(15))
    }

    /// Overlapping blocks (e.g. a schedule during a manual lock) count once.
    private static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        var result: [(Date, Date)] = []
        for interval in intervals.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, interval.0 <= last.1 {
                result[result.count - 1].1 = max(last.1, interval.1)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    static func format(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : UsageLimit.formatted(minutes: minutes)
    }
}
