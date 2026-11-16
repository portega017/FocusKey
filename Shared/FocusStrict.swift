//
//  FocusStrict.swift
//  FocusKey
//
//  Strict mode: any change that could make blocking weaker needs the NFC tag; changes that only
//  make it stricter (adding apps, days or schedules, enabling things) stay free. These rules are
//  pure so they can be tested; FocusModel enforces them.
//

import Foundation
import FamilyControls

nonisolated extension FocusSchedule {
    /// Whether replacing `self` with `new` could block less. A disabled schedule blocks nothing,
    /// so editing it is free (turning it on is stricter anyway).
    func isWeakened(by new: FocusSchedule, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        if !new.isEnabled { return true }
        if new.profileID != profileID { return true }
        if !new.repeats.isSuperset(of: repeats) { return true }
        if !new.pausedDays.allSatisfy({ day in pausedDays.contains { calendar.isDate($0, inSameDayAs: day) } }) {
            return true
        }
        return !new.covers(self, calendar: calendar)
    }

    /// Whether this interval contains `other`'s on any day (both measured from the same start day).
    private func covers(_ other: FocusSchedule, calendar: Calendar) -> Bool {
        func span(_ schedule: FocusSchedule) -> (Int, Int) {
            let start = Self.minutes(schedule.startTime, calendar: calendar)
            var end = Self.minutes(schedule.endTime, calendar: calendar)
            if end <= start { end += 24 * 60 }
            return (start, end)
        }
        let (start, end) = span(self)
        let (otherStart, otherEnd) = span(other)
        return start <= otherStart && end >= otherEnd
    }
}

nonisolated extension UsageLimit {
    /// More minutes, another profile or turning it off all allow more use.
    func isWeakened(by new: UsageLimit) -> Bool {
        guard isEnabled else { return false }
        return !new.isEnabled || new.minutes > minutes || new.profileID != profileID
    }
}

nonisolated extension FocusProfile {
    /// Removing any app, category or website lets it through wherever the profile is used.
    func isWeakened(by new: FocusProfile) -> Bool {
        !new.selection.applicationTokens.isSuperset(of: selection.applicationTokens)
            || !new.selection.categoryTokens.isSuperset(of: selection.categoryTokens)
            || !new.selection.webDomainTokens.isSuperset(of: selection.webDomainTokens)
    }
}
