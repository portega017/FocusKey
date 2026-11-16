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
}
