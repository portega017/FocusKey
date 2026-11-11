//
//  FocusKeyTests.swift
//  FocusKeyTests
//
//  Logic tests for the shared code (schedules, limits, statistics, storage migration).
//  Screen Time itself can only be tested on a physical device.
//

import Foundation
import Testing
@testable import FocusKey

/// Fixed calendar so results don't depend on the machine running the tests.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()

/// November 2026: the 6th is a Friday, the 7th a Saturday, the 8th a Sunday.
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func time(_ hour: Int, _ minute: Int = 0) -> Date {
    date(1, hour, minute)
}

@Suite("Schedules")
struct ScheduleTests {
    let workdays: Set<FocusWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    @Test func activeInsideSameDayInterval() {
        let schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays)
        #expect(schedule.isActive(at: date(6, 9), calendar: calendar))
        #expect(schedule.isActive(at: date(6, 16, 59), calendar: calendar))
        #expect(!schedule.isActive(at: date(6, 17), calendar: calendar), "End time is exclusive")
        #expect(!schedule.isActive(at: date(6, 8, 59), calendar: calendar))
    }

    @Test func inactiveOnUnselectedDayOrWhenDisabled() {
        var schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays)
        #expect(!schedule.isActive(at: date(7, 12), calendar: calendar), "Saturday isn't selected")
        schedule.isEnabled = false
        #expect(!schedule.isActive(at: date(6, 12), calendar: calendar))
    }

    @Test func overnightIntervalBelongsToTheDayItStarts() {
        let fridayNight = FocusSchedule(startTime: time(23), endTime: time(7), repeats: [.friday])
        #expect(fridayNight.crossesMidnight)
        #expect(fridayNight.isActive(at: date(6, 23, 30), calendar: calendar))
        #expect(fridayNight.isActive(at: date(7, 6), calendar: calendar), "Saturday morning is still Friday's interval")
        #expect(!fridayNight.isActive(at: date(7, 23, 30), calendar: calendar), "Saturday night isn't selected")

        let saturdayNight = FocusSchedule(startTime: time(23), endTime: time(7), repeats: [.saturday])
        #expect(!saturdayNight.isActive(at: date(7, 6), calendar: calendar), "Friday's night isn't selected")
    }

    @Test func intervalEndIsTheNextEndTime() {
        let schedule = FocusSchedule(startTime: time(23), endTime: time(7), repeats: [.friday])
        #expect(schedule.intervalEnd(after: date(6, 23, 30), calendar: calendar) == date(7, 7))
        #expect(schedule.intervalEnd(after: date(7, 6), calendar: calendar) == date(7, 7))
    }

    @Test func decodesSchedulesFromOlderVersions() throws {
        // First versions stored a single "time" and no end time, name or profile.
        let start = time(10)
        let json = """
        [{"id":"\(UUID().uuidString)","time":\(start.timeIntervalSinceReferenceDate),"repeats":["monday"],"isEnabled":true}]
        """
        let schedules = try JSONDecoder().decode([FocusSchedule].self, from: Data(json.utf8))
        let schedule = try #require(schedules.first)
        #expect(schedule.name.isEmpty)
        #expect(schedule.profileID == nil)
        #expect(schedule.endTime == start.addingTimeInterval(15 * 60))
    }

    @Test func weekSegmentsSplitOvernightIntervals() {
        let night = FocusSchedule(startTime: time(23), endTime: time(7), repeats: [.sunday])
        let segments = night.weekSegments(calendar: calendar)
        #expect(segments.count == 2)
        #expect(segments.contains(.init(weekday: .sunday, startMinute: 23 * 60, endMinute: 24 * 60)))
        #expect(segments.contains(.init(weekday: .monday, startMinute: 0, endMinute: 7 * 60)), "Sunday night wraps to Monday")

        let midnightEnd = FocusSchedule(startTime: time(22), endTime: time(0), repeats: [.friday])
        #expect(midnightEnd.weekSegments(calendar: calendar) == [.init(weekday: .friday, startMinute: 22 * 60, endMinute: 24 * 60)])

        var disabled = night
        disabled.isEnabled = false
        #expect(disabled.weekSegments(calendar: calendar).isEmpty)
    }

    @Test func deviceActivityScheduleRejectsEmptyOrZeroLength() {
        #expect(FocusSchedule(startTime: time(9), endTime: time(10), repeats: []).deviceActivitySchedule == nil)
        #expect(FocusSchedule(startTime: time(9), endTime: time(9), repeats: workdays).deviceActivitySchedule == nil)
        #expect(FocusSchedule(startTime: time(9), endTime: time(10), repeats: workdays).deviceActivitySchedule != nil)
    }
}

@Suite("Usage limits")
struct LimitTests {
    @Test(arguments: [(2, nil), (3, 1), (14, 1), (15, 5), (90, 5)] as [(Int, Int?)])
    func warningLead(minutes: Int, lead: Int?) {
        #expect(UsageLimit(profileID: nil, minutes: minutes).warningLeadMinutes == lead)
    }

    @Test func eventsIncludeWarningOnlyWhenItFits() {
        let selection = FocusProfile(name: "Test").selection
        #expect(UsageLimit(profileID: nil, minutes: 2).events(for: selection).count == 1)
        #expect(UsageLimit(profileID: nil, minutes: 30).events(for: selection).count == 2)
    }

    @Test(arguments: [(5, "5 min"), (60, "1 h"), (90, "1 h 30 min"), (125, "2 h 5 min")])
    func formatsMinutes(minutes: Int, text: String) {
        #expect(UsageLimit.formatted(minutes: minutes) == text)
    }
}

@Suite("Statistics")
struct StatsTests {
    private func record(_ start: Date, _ end: Date?) -> BlockRecord {
        BlockRecord(kind: .manual, title: "Test", sourceID: UUID().uuidString, start: start, end: end)
    }

    @Test func overlappingBlocksCountOnce() {
        let records = [record(date(8, 9), date(8, 11)), record(date(8, 10), date(8, 12))]
        let stats = FocusStats(records: records, now: date(8, 20), calendar: calendar)
        #expect(stats.today == 180)
    }

    @Test func blockAcrossMidnightIsSplitBetweenDays() {
        let stats = FocusStats(records: [record(date(7, 23), date(8, 1))], now: date(8, 20), calendar: calendar)
        #expect(stats.today == 60)
        #expect(stats.week.first { calendar.isDate($0.date, inSameDayAs: date(7, 12)) }?.minutes == 60)
    }

    @Test func runningBlockCountsUntilNow() {
        let stats = FocusStats(records: [record(date(8, 18), nil)], now: date(8, 19, 30), calendar: calendar)
        #expect(stats.today == 90)
    }

    @Test func streakCountsConsecutiveDays() {
        let records = [
            record(date(5, 10), date(5, 11)),
            record(date(6, 10), date(6, 11)),
            record(date(7, 10), date(7, 11))
        ]
        // Nothing today yet: the streak still counts up to yesterday.
        #expect(FocusStats(records: records, now: date(8, 9), calendar: calendar).streak == 3)
        // A gap breaks it.
        #expect(FocusStats(records: Array(records.dropLast()), now: date(8, 9), calendar: calendar).streak == 0)
    }

    @Test func calendarHasFiveMondayFirstWeeks() {
        // Sunday the 8th: the current week started on Monday the 2nd.
        let stats = FocusStats(records: [record(date(8, 10), date(8, 11))], now: date(8, 12), calendar: calendar)
        #expect(stats.calendarDays.count == 35)
        #expect(calendar.component(.weekday, from: stats.calendarDays.first!.date) == 2, "Starts on a Monday")
        #expect(calendar.isDate(stats.calendarDays.last!.date, inSameDayAs: date(8, 12)), "Ends on this Sunday")
        #expect(stats.calendarDays.last?.minutes == 60)
    }

    @Test func weekHasSevenDaysEndingToday() {
        let stats = FocusStats(records: [], now: date(8, 12), calendar: calendar)
        #expect(stats.week.count == 7)
        #expect(calendar.isDate(stats.week.last!.date, inSameDayAs: date(8, 12)))
    }
}

@Suite("Shield helpers")
struct ShieldTests {
    @Test func unionOfEmptySelectionsIsNil() {
        #expect(FocusLock.union([]) == nil)
        #expect(FocusLock.union([FocusProfile(name: "A").selection]) == nil)
    }

    @Test func profileSummaryWhenEmpty() {
        #expect(FocusProfile(name: "").displayName == "Perfil sin nombre")
        #expect(FocusProfile(name: "Trabajo").isEmpty)
    }
}

@Suite("Profiles and sessions")
struct ProfileTests {
    @Test func decodesProfilesSavedBeforeColors() throws {
        // Older builds didn't store colorName; those profiles must still load.
        let data = try JSONEncoder().encode([FocusProfile(name: "Trabajo", symbol: "briefcase.fill")])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        json[0].removeValue(forKey: "colorName")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let profiles = try JSONDecoder().decode([FocusProfile].self, from: legacy)
        #expect(profiles.first?.name == "Trabajo")
        #expect(profiles.first?.symbol == "briefcase.fill")
        #expect(profiles.first?.colorName == "indigo")
    }

    @Test func nextColorAvoidsUsedOnes() {
        let profiles = [FocusProfile(name: "A", colorName: "indigo"), FocusProfile(name: "B", colorName: "blue")]
        #expect(FocusPalette.nextName(after: profiles) == "teal")
    }

    @Test func sessionProgressGoesFromZeroToOne() {
        let status = FocusStatus(date: date(8, 10), manualProfile: nil, isManualLocked: true,
                                 sessionEnd: date(8, 11), sessionStart: date(8, 10), schedules: [], limits: [])
        #expect(status.sessionProgress(at: date(8, 10)) == 0)
        #expect(status.sessionProgress(at: date(8, 10, 30)) == 0.5)
        #expect(status.sessionProgress(at: date(8, 12)) == 1)
    }
}
