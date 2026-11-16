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

@Suite("Paused schedule days")
struct PausedScheduleTests {
    let workdays: Set<FocusWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    @Test func pausedDayDoesNotBlock() {
        // Thursday the 5th is paused, Friday the 6th isn't.
        let schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays,
                                     pausedDays: [calendar.startOfDay(for: date(5, 0))])
        #expect(!schedule.isActive(at: date(5, 12), calendar: calendar))
        #expect(schedule.isActive(at: date(6, 12), calendar: calendar))
        #expect(!schedule.runs(on: date(5, 0), calendar: calendar))
    }

    @Test func pausingTheStartDayCoversTheOvernightMorning() {
        let night = FocusSchedule(startTime: time(23), endTime: time(7), repeats: [.friday, .saturday],
                                  pausedDays: [calendar.startOfDay(for: date(6, 0))])
        #expect(!night.isActive(at: date(6, 23, 30), calendar: calendar), "Friday night is paused")
        #expect(!night.isActive(at: date(7, 6), calendar: calendar), "Saturday morning belongs to Friday's paused interval")
        #expect(night.isActive(at: date(7, 23, 30), calendar: calendar), "Saturday night still runs")
    }

    @Test func upcomingDaysSkipIntervalsAlreadyStarted() {
        let schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays)
        // Thursday 5th at 10:00: today's interval has started, so the next one is Friday.
        let days = schedule.upcomingDays(after: date(5, 10), limit: 3, calendar: calendar)
        #expect(days == [date(6, 0), date(9, 0), date(10, 0)], "Friday, then Monday and Tuesday")
        // Before 9:00 today is still pausable.
        #expect(schedule.upcomingDays(after: date(5, 8), limit: 1, calendar: calendar) == [date(5, 0)])
    }

    @Test func oldPausesArePruned() {
        let schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays,
                                     pausedDays: [date(2, 0), date(5, 0), date(9, 0)])
        #expect(schedule.prunedPauses(at: date(6, 12), calendar: calendar) == [date(5, 0), date(9, 0)])
    }

    @Test func pausesSurviveEncodingAndOldDataHasNone() throws {
        let schedule = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays, pausedDays: [date(9, 0)])
        let decoded = try JSONDecoder().decode(FocusSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(decoded.pausedDays == [date(9, 0)])

        let plain = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(json["pausedDays"] == nil, "Nothing new is written when there are no pauses")
        #expect(try JSONDecoder().decode(FocusSchedule.self, from: JSONEncoder().encode(plain)).pausedDays.isEmpty)
    }
}

@Suite("Pomodoro")
struct PomodoroTests {
    /// 3 cycles of 25 + 5 starting at 10:00: focus 10:00–10:25, 10:30–10:55, 11:00–11:25.
    let plan = PomodoroPlan(profileID: UUID(), start: date(8, 10), focusMinutes: 25, breakMinutes: 5, cycles: 3)

    @Test func blocksAreSpacedByFocusPlusBreak() {
        #expect(plan.block(0) == DateInterval(start: date(8, 10), end: date(8, 10, 25)))
        #expect(plan.block(2) == DateInterval(start: date(8, 11), end: date(8, 11, 25)))
        #expect(plan.end == date(8, 11, 25), "No break after the last block")
        #expect(plan.totalFocusMinutes == 75)
    }

    @Test func phasesFollowTheClock() {
        #expect(plan.phase(at: date(8, 10)) == .focus(cycle: 0, start: date(8, 10), end: date(8, 10, 25)))
        #expect(plan.phase(at: date(8, 10, 24)) == .focus(cycle: 0, start: date(8, 10), end: date(8, 10, 25)))
        #expect(plan.phase(at: date(8, 10, 25)) == .rest(cycle: 0, start: date(8, 10, 25), end: date(8, 10, 30)))
        #expect(plan.phase(at: date(8, 10, 30)) == .focus(cycle: 1, start: date(8, 10, 30), end: date(8, 10, 55)))
        #expect(plan.phase(at: date(8, 11, 24)) == .focus(cycle: 2, start: date(8, 11), end: date(8, 11, 25)))
        #expect(plan.phase(at: date(8, 11, 25)) == .finished)
        #expect(plan.isFinished(at: date(8, 12)))
    }

    @Test func statusDuringABreakIsNotBlockedButTheKeyEndsIt() {
        let status = FocusStatus(date: date(8, 10, 27), manualProfile: nil, isManualLocked: false,
                                 sessionEnd: nil, sessionStart: nil, schedules: [], limits: [], pomodoro: plan)
        #expect(!status.isBlocked)
        #expect(status.canUnlockWithKey, "The tag ends the whole pomodoro, breaks included")
        #expect(status.nextChange == date(8, 10, 30))
        #expect(status.pomodoroCycleText == "Ciclo 2 de 3")
    }

    @Test func activityNamesRoundTrip() {
        #expect(FocusActivity.pomodoroCycle(from: FocusActivity.pomodoro(4)) == 4)
        #expect(FocusActivity.pomodoroCycle(from: FocusActivity.session) == nil)
        #expect(FocusActivity.scheduleID(from: FocusActivity.pomodoro(1)) == nil)
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

@Suite("Yearly focus")
struct YearStatsTests {
    private func record(_ start: Date, _ end: Date) -> BlockRecord {
        BlockRecord(kind: .manual, title: "", sourceID: UUID().uuidString, start: start, end: end)
    }

    @Test func archivedDaysComeFromTheArchiveAndNewerOnesFromRecords() {
        // Days before the 3rd are archived; a stray record on the 1st must not be counted twice.
        let counter = FocusStats.DayCounter(
            records: [record(date(1, 10), date(1, 11)), record(date(4, 10), date(4, 12))],
            archive: ["2026-11-01": 30, "2026-11-02": 45],
            archivedUntil: date(3, 0),
            now: date(8, 12),
            calendar: calendar
        )
        #expect(counter.minutes(on: date(1, 0)) == 30)
        #expect(counter.minutes(on: date(2, 0)) == 45)
        #expect(counter.minutes(on: date(4, 0)) == 120)
        #expect(counter.minutes(on: date(5, 0)) == 0)
    }

    @Test func yearSummaryAddsMonthsAndDays() {
        let counter = FocusStats.DayCounter(
            records: [record(date(4, 10), date(4, 12)), record(date(6, 9), date(6, 9, 30))],
            archive: ["2026-01-15": 60, "2026-03-02": 90],
            archivedUntil: date(1, 0),
            now: date(8, 12),
            calendar: calendar
        )
        let stats = FocusYearStats(year: 2026, counter: counter, now: date(8, 12))
        #expect(stats.days.count == 365)
        #expect(stats.total == 60 + 90 + 120 + 30)
        #expect(stats.activeDays == 4)
        #expect(stats.months.count == 12)
        #expect(stats.months[0].minutes == 60)
        #expect(stats.months[2].minutes == 90)
        #expect(stats.months[10].minutes == 150, "November")
        #expect(stats.bestDay?.minutes == 120)
        // November 8th is day 312 of the year.
        #expect(stats.dailyAverage == 300 / 312)
    }

    @Test func emptyYearHasNoBestDay() {
        let counter = FocusStats.DayCounter(records: [], now: date(8, 12), calendar: calendar)
        let stats = FocusYearStats(year: 2026, counter: counter, now: date(8, 12))
        #expect(stats.total == 0)
        #expect(stats.bestDay == nil)
    }

    @Test func yearsIncludeArchivedOnesAndTheCurrentOne() {
        let counter = FocusStats.DayCounter(records: [], archive: ["2025-06-01": 10], archivedUntil: date(1, 0),
                                            now: date(8, 12), calendar: calendar)
        #expect(counter.years(now: date(8, 12)) == [2025, 2026])
    }

    @Test func dayKeyIsZeroPadded() {
        #expect(FocusStats.dayKey(date(8, 23, 59), calendar: calendar) == "2026-11-08")
    }
}

@Suite("Session presets")
struct PresetTests {
    @Test func titleUsesNameOrProfile() {
        let profile = FocusProfile(name: "Redes")
        let unnamed = SessionPreset(profileID: profile.id, minutes: 60)
        #expect(unnamed.title(profile: profile) == "Redes · 1 h")
        let named = SessionPreset(name: "Sin móvil", profileID: profile.id, minutes: 90)
        #expect(named.title(profile: profile) == "Sin móvil · 1 h 30 min")
    }

    @Test func presetsRoundTrip() throws {
        let presets = [SessionPreset(name: "A", profileID: UUID(), minutes: 45), SessionPreset(profileID: UUID())]
        let decoded = try JSONDecoder().decode([SessionPreset].self, from: JSONEncoder().encode(presets))
        #expect(decoded == presets)
        #expect(decoded[1].minutes == 60, "Default is one hour")
    }

    @Test func durationOptionsRespectTheSessionMinimum() {
        #expect(SessionPreset.durationOptions.allSatisfy { $0 >= FocusLock.minimumSessionMinutes })
    }
}

@Suite("Strict mode rules")
struct StrictModeTests {
    let workdays: Set<FocusWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    @Test func scheduleChangesThatBlockLessAreWeakening() {
        let base = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays, profileID: UUID())
        var copy = base

        copy.isEnabled = false
        #expect(base.isWeakened(by: copy, calendar: calendar), "Turning it off")

        copy = base; copy.repeats.remove(.friday)
        #expect(base.isWeakened(by: copy, calendar: calendar), "Removing a day")

        copy = base; copy.startTime = time(10)
        #expect(base.isWeakened(by: copy, calendar: calendar), "Starting later")

        copy = base; copy.endTime = time(16)
        #expect(base.isWeakened(by: copy, calendar: calendar), "Ending earlier")

        copy = base; copy.profileID = UUID()
        #expect(base.isWeakened(by: copy, calendar: calendar), "Another profile")

        copy = base; copy.pausedDays = [date(9, 0)]
        #expect(base.isWeakened(by: copy, calendar: calendar), "Adding a pause")
    }

    @Test func scheduleChangesThatBlockMoreAreFree() {
        let base = FocusSchedule(startTime: time(9), endTime: time(17), repeats: workdays,
                                 profileID: UUID(), pausedDays: [date(9, 0)])
        var copy = base

        copy.repeats.insert(.saturday)
        copy.startTime = time(8)
        copy.endTime = time(18)
        copy.name = "Más largo"
        copy.pausedDays = []
        #expect(!base.isWeakened(by: copy, calendar: calendar))

        copy = base; copy.endTime = time(1)
        #expect(!base.isWeakened(by: copy, calendar: calendar), "Extending past midnight covers the old interval")

        var disabled = base
        disabled.isEnabled = false
        var edited = disabled
        edited.repeats = [.monday]
        #expect(!disabled.isWeakened(by: edited, calendar: calendar), "A disabled schedule blocks nothing")
    }

    @Test func limitChangesThatAllowMoreUseAreWeakening() {
        let base = UsageLimit(profileID: UUID(), minutes: 30)
        var copy = base
        copy.minutes = 45
        #expect(base.isWeakened(by: copy))
        copy = base; copy.isEnabled = false
        #expect(base.isWeakened(by: copy))
        copy = base; copy.profileID = UUID()
        #expect(base.isWeakened(by: copy))
        copy = base; copy.minutes = 15; copy.name = "Menos"
        #expect(!base.isWeakened(by: copy), "Lowering the limit is stricter")
    }

    @Test func profileWithTheSameAppsIsNotWeakened() {
        let profile = FocusProfile(name: "Redes")
        var renamed = profile
        renamed.name = "Social"
        renamed.colorName = "red"
        #expect(!profile.isWeakened(by: renamed), "Name and color don't change what is blocked")
    }
}

@Suite("Pomodoro presets")
struct PomodoroPresetTests {
    @Test func titleShowsCyclesAndFocus() {
        let profile = FocusProfile(name: "Estudio")
        let preset = SessionPreset(profileID: profile.id, pomodoro: .init(focusMinutes: 25, breakMinutes: 5, cycles: 4))
        #expect(preset.title(profile: profile) == "Estudio · 4×25")
        #expect(SessionPreset(profileID: profile.id, minutes: 60).durationText == "1 h")
    }

    @Test func presetsSavedBeforePomodorosStillLoad() throws {
        // Earlier builds stored id, name, profileID and minutes only.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Redes","profileID":"\(UUID().uuidString)","minutes":60}]
        """
        let presets = try JSONDecoder().decode([SessionPreset].self, from: Data(json.utf8))
        #expect(presets.first?.pomodoro == nil)
        #expect(presets.first?.minutes == 60)
    }

    @Test func pomodoroPresetRoundTrips() throws {
        let preset = SessionPreset(name: "Estudio", profileID: UUID(), pomodoro: .init(focusMinutes: 50, breakMinutes: 10, cycles: 3))
        let decoded = try JSONDecoder().decode(SessionPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)
    }

    @Test func defaultPomodoroFitsThePlanLimits() {
        let pomodoro = SessionPreset.Pomodoro()
        #expect(PomodoroPlan.focusOptions.contains(pomodoro.focusMinutes))
        #expect(PomodoroPlan.breakOptions.contains(pomodoro.breakMinutes))
        #expect(PomodoroPlan.cycleRange.contains(pomodoro.cycles))
    }
}

@Suite("Tightening a running block")
struct TighteningTests {
    /// 3 cycles of 25 + 5 from 10:00: focus 10:00–10:25, 10:30–10:55, 11:00–11:25.
    let plan = PomodoroPlan(profileID: UUID(), start: date(8, 10), focusMinutes: 25, breakMinutes: 5, cycles: 3)

    @Test func skippingABreakStartsTheNextBlockNow() throws {
        let shifted = try #require(plan.skippingBreak(at: date(8, 10, 27)))
        #expect(shifted.phase(at: date(8, 10, 27)) == .focus(cycle: 1, start: date(8, 10, 27), end: date(8, 10, 52)))
        #expect(shifted.block(2).start == date(8, 10, 57), "Later blocks move earlier by the same 3 minutes")
        #expect(shifted.end == date(8, 11, 22))
    }

    @Test func breaksCanOnlyBeSkippedDuringABreak() {
        #expect(plan.skippingBreak(at: date(8, 10, 10)) == nil, "During focus")
        #expect(plan.skippingBreak(at: date(8, 12)) == nil, "After the end")
    }
}
