//
//  FocusStats.swift
//  FocusKey
//
//  Statistics computed from block records: minutes blocked per day, streak and the yearly summary.
//  Records are kept for 60 days; older days survive as per-day totals in FocusStore's daily
//  archive, so the year view keeps counting after their records are gone.
//

import Foundation

nonisolated struct FocusStats {
    struct Day: Identifiable {
        var date: Date
        var minutes: Int
        var id: Date { date }
    }

    /// Minutes blocked on any day: from the archive for days before `archivedUntil`,
    /// otherwise from the records (overlapping blocks merged).
    struct DayCounter {
        let intervals: [(Date, Date)]
        let archive: [String: Int]
        let archivedUntil: Date?
        let calendar: Calendar

        init(records: [BlockRecord], archive: [String: Int] = [:], archivedUntil: Date? = nil,
             now: Date = .now, calendar: Calendar = .current) {
            intervals = FocusStats.merged(records.map { ($0.start, min($0.end ?? now, now)) })
            self.archive = archive
            self.archivedUntil = archivedUntil
            self.calendar = calendar
        }

        func minutes(on dayStart: Date) -> Int {
            if let archivedUntil, dayStart < archivedUntil {
                return archive[FocusStats.dayKey(dayStart, calendar: calendar)] ?? 0
            }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let seconds = intervals.reduce(0.0) { total, interval in
                let start = max(interval.0, dayStart)
                let end = min(interval.1, dayEnd)
                return total + max(0, end.timeIntervalSince(start))
            }
            return Int(seconds / 60)
        }

        /// Years with any recorded focus, plus the current one.
        func years(now: Date = .now) -> [Int] {
            var years = Set([calendar.component(.year, from: now)])
            for key in archive.keys { if let year = Int(key.prefix(4)) { years.insert(year) } }
            for interval in intervals { years.insert(calendar.component(.year, from: interval.0)) }
            return years.sorted()
        }
    }

    let week: [Day]
    /// Five full weeks (Monday to Sunday) ending with the current one, for the calendar.
    /// Days after today are included with 0 minutes so the grid stays aligned.
    let calendarDays: [Day]
    let today: Int
    let streak: Int
    let recent: [BlockRecord]

    init(records: [BlockRecord], archive: [String: Int] = [:], archivedUntil: Date? = nil,
         now: Date = .now, calendar: Calendar = .current) {
        let counter = DayCounter(records: records, archive: archive, archivedUntil: archivedUntil, now: now, calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)

        week = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayStart).map { Day(date: $0, minutes: counter.minutes(on: $0)) }
        }
        today = counter.minutes(on: todayStart)

        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let thisWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let firstDay = calendar.date(byAdding: .day, value: -28, to: thisWeek) ?? thisWeek
        calendarDays = (0..<35).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return Day(date: day, minutes: day > now ? 0 : counter.minutes(on: day))
        }

        // Consecutive days with at least one minute blocked; today counts only once it has some.
        var streak = 0
        var day = today > 0 ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while counter.minutes(on: day) > 0, streak < 365 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        self.streak = streak

        recent = Array(records.sorted { $0.start > $1.start }.prefix(15))
    }

    /// Overlapping blocks (e.g. a schedule during a manual lock) count once.
    static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
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

    /// "2026-11-08": stable key for a day in the archive, independent of the time zone offset.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func format(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : UsageLimit.formatted(minutes: minutes)
    }
}

// MARK: - Year

/// Focus time over one calendar year.
nonisolated struct FocusYearStats {
    struct Month: Identifiable {
        var date: Date
        var minutes: Int
        var id: Date { date }
    }

    let year: Int
    /// Every day of the year; days after today have 0 minutes.
    let days: [FocusStats.Day]
    let months: [Month]
    let total: Int
    /// Days with at least one minute of focus.
    let activeDays: Int
    let bestDay: FocusStats.Day?
    /// Average per elapsed day of the year (whole year for past years).
    let dailyAverage: Int

    init(year: Int, counter: FocusStats.DayCounter, now: Date = .now) {
        let calendar = counter.calendar
        self.year = year
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let next = calendar.date(byAdding: .year, value: 1, to: start) ?? now
        let dayCount = calendar.dateComponents([.day], from: start, to: next).day ?? 365

        let days: [FocusStats.Day] = (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return FocusStats.Day(date: day, minutes: day > now ? 0 : counter.minutes(on: day))
        }
        self.days = days
        months = (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            let minutes = days.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }.reduce(0) { $0 + $1.minutes }
            return Month(date: month, minutes: minutes)
        }
        let total = days.reduce(0) { $0 + $1.minutes }
        self.total = total
        activeDays = days.filter { $0.minutes > 0 }.count
        bestDay = days.max { $0.minutes < $1.minutes }.flatMap { $0.minutes > 0 ? $0 : nil }

        let elapsed = now >= next ? dayCount : max(1, (calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1)
        dailyAverage = now < start ? 0 : total / elapsed
    }
}
