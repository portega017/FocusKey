//
//  FocusModels.swift
//  FocusKey
//
//  Data types shared by the app and all its extensions.
//

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// MARK: - Profile

/// A named set of apps, categories and websites to block.
nonisolated struct FocusProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var symbol: String
    var selection: FamilyActivitySelection

    init(id: UUID = UUID(), name: String, symbol: String = "lock.shield", selection: FamilyActivitySelection = .init()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.selection = selection
    }

    var displayName: String { name.isEmpty ? String(localized: "Perfil sin nombre") : name }

    var isEmpty: Bool {
        selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    var summary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let webs = selection.webDomainTokens.count
        guard apps + categories + webs > 0 else { return String(localized: "Nada seleccionado") }
        var parts: [String] = []
        if apps > 0 { parts.append(String(localized: "\(apps) apps")) }
        if categories > 0 { parts.append(String(localized: "\(categories) categorías")) }
        if webs > 0 { parts.append(String(localized: "\(webs) webs")) }
        return parts.joined(separator: " · ")
    }

    func contains(_ token: ApplicationToken) -> Bool { selection.applicationTokens.contains(token) }
    func contains(_ token: ActivityCategoryToken) -> Bool { selection.categoryTokens.contains(token) }
    func contains(_ token: WebDomainToken) -> Bool { selection.webDomainTokens.contains(token) }

    static let symbols = [
        "lock.shield", "briefcase.fill", "book.fill", "moon.fill", "gamecontroller.fill",
        "bubble.left.and.bubble.right.fill", "play.tv.fill", "cart.fill", "figure.run",
        "fork.knife", "graduationcap.fill", "house.fill"
    ]
}

// MARK: - Weekday

nonisolated enum FocusWeekday: String, Codable, CaseIterable, Identifiable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return String(localized: "Dom")
        case .monday: return String(localized: "Lun")
        case .tuesday: return String(localized: "Mar")
        case .wednesday: return String(localized: "Mié")
        case .thursday: return String(localized: "Jue")
        case .friday: return String(localized: "Vie")
        case .saturday: return String(localized: "Sáb")
        }
    }

    /// Calendar weekday value (1 = Sunday … 7 = Saturday).
    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    static func of(_ date: Date, calendar: Calendar = .current) -> FocusWeekday {
        let value = calendar.component(.weekday, from: date)
        return allCases.first { $0.calendarWeekday == value } ?? .sunday
    }
}

// MARK: - Schedule

/// A weekly interval during which a profile is blocked.
nonisolated struct FocusSchedule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var startTime: Date
    var endTime: Date
    var repeats: Set<FocusWeekday>
    var isEnabled: Bool
    /// Profile to block. `nil` (schedules from older versions) means the first profile.
    var profileID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "",
        startTime: Date,
        endTime: Date,
        repeats: Set<FocusWeekday>,
        isEnabled: Bool = true,
        profileID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.repeats = repeats
        self.isEnabled = isEnabled
        self.profileID = profileID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startTime, endTime, time, repeats, isEnabled, profileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
            ?? container.decode(Date.self, forKey: .time)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
            ?? startTime.addingTimeInterval(15 * 60)
        repeats = try container.decode(Set<FocusWeekday>.self, forKey: .repeats)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(repeats, forKey: .repeats)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(profileID, forKey: .profileID)
    }

    var displayName: String { name.isEmpty ? String(localized: "Horario de concentración") : name }

    var activityName: DeviceActivityName { FocusActivity.schedule(id) }

    /// Daily monitor interval. The monitor extension filters callbacks by weekday.
    var deviceActivitySchedule: DeviceActivitySchedule? {
        guard !repeats.isEmpty else { return nil }
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: startTime)
        let end = calendar.dateComponents([.hour, .minute], from: endTime)
        guard Self.minutes(startTime) != Self.minutes(endTime) else { return nil }
        // If end is earlier than start (e.g. 23:00–07:00), iOS ends the interval the next day.
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: start.hour, minute: start.minute),
            intervalEnd: DateComponents(hour: end.hour, minute: end.minute),
            repeats: true
        )
    }

    var crossesMidnight: Bool { Self.minutes(startTime) > Self.minutes(endTime) }

    /// True while the interval is running (ignores NFC skips).
    func isActive(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let now = Self.minutes(date, calendar: calendar)
        let start = Self.minutes(startTime, calendar: calendar)
        let end = Self.minutes(endTime, calendar: calendar)

        if start < end {
            return repeats.contains(.of(date, calendar: calendar)) && now >= start && now < end
        }
        if now >= start {
            return repeats.contains(.of(date, calendar: calendar))
        }
        guard now < end, let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else {
            return false
        }
        return repeats.contains(.of(yesterday, calendar: calendar))
    }

    /// Next occurrence of the end time after `date` (end of the running interval).
    func intervalEnd(after date: Date, calendar: Calendar = .current) -> Date {
        let end = calendar.dateComponents([.hour, .minute], from: endTime)
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: end.hour, minute: end.minute),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(24 * 60 * 60)
    }

    static func minutes(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

// MARK: - Usage limit

/// Blocks a profile for the rest of the day once it has been used for `minutes`.
nonisolated struct UsageLimit: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var profileID: UUID?
    var minutes: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String = "", profileID: UUID?, minutes: Int = 30, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.minutes = minutes
        self.isEnabled = isEnabled
    }

    var displayName: String { name.isEmpty ? String(localized: "Límite diario") : name }

    var activityName: DeviceActivityName { FocusActivity.limit(id) }

    static let eventName = DeviceActivityEvent.Name("FocusKey.limitReached")

    /// Whole day, repeating. Ends at 23:59 because an interval can't end at 00:00 of the same day.
    static let dailySchedule = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true
    )

    static let extraEventName = DeviceActivityEvent.Name("FocusKey.extraUsed")

    /// Extra minutes granted with the NFC tag, counted from now (past usage ignored).
    static func extraEvent(minutes: Int, selection: FamilyActivitySelection) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
            includesPastActivity: false
        )
    }

    static let warningEventName = DeviceActivityEvent.Name("FocusKey.limitWarning")

    /// Minutes left when the warning is sent: 5 for limits of 15 min or more, 1 for shorter ones.
    var warningLeadMinutes: Int? {
        if minutes >= 15 { return 5 }
        if minutes >= 3 { return 1 }
        return nil
    }

    /// The limit event plus, when it makes sense, a warning a few minutes earlier.
    func events(for selection: FamilyActivitySelection) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events = [Self.eventName: event(for: selection)]
        if let lead = warningLeadMinutes {
            let at = minutes - lead
            events[Self.warningEventName] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(hour: at / 60, minute: at % 60),
                includesPastActivity: true
            )
        }
        return events
    }

    func event(for selection: FamilyActivitySelection) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
            includesPastActivity: true
        )
    }

    static func formatted(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return String(localized: "\(hours) h \(rest) min")
        }
    }
}

// MARK: - Block record (statistics)

nonisolated struct BlockRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case manual, session, schedule, limit

        var label: String {
            switch self {
            case .manual: return String(localized: "Bloqueo manual")
            case .session: return String(localized: "Sesión")
            case .schedule: return String(localized: "Horario")
            case .limit: return String(localized: "Límite diario")
            }
        }

        var symbol: String {
            switch self {
            case .manual: return "lock.fill"
            case .session: return "timer"
            case .schedule: return "calendar.badge.clock"
            case .limit: return "hourglass"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var title: String
    /// What produced the block ("manual", or a schedule/limit UUID), used to close it.
    var sourceID: String
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), kind: Kind, title: String, sourceID: String, start: Date, end: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceID = sourceID
        self.start = start
        self.end = end
    }
}

// MARK: - Activity names

nonisolated enum FocusActivity {
    static let schedulePrefix = "FocusKeySchedule_"
    static let limitPrefix = "FocusKeyLimit_"
    /// Extra time granted with the tag after a limit was reached.
    static let extraPrefix = "FocusKeyExtra_"
    static let session = DeviceActivityName("FocusKeySession")

    static func schedule(_ id: UUID) -> DeviceActivityName { .init(schedulePrefix + id.uuidString) }
    static func limit(_ id: UUID) -> DeviceActivityName { .init(limitPrefix + id.uuidString) }
    static func extra(_ id: UUID) -> DeviceActivityName { .init(extraPrefix + id.uuidString) }

    static func extraID(from activity: DeviceActivityName) -> UUID? {
        id(from: activity, prefix: extraPrefix)
    }

    static func scheduleID(from activity: DeviceActivityName) -> UUID? {
        id(from: activity, prefix: schedulePrefix)
    }

    static func limitID(from activity: DeviceActivityName) -> UUID? {
        id(from: activity, prefix: limitPrefix)
    }

    private static func id(from activity: DeviceActivityName, prefix: String) -> UUID? {
        guard activity.rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(prefix.count)))
    }
}
