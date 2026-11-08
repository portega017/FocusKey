//
//  FocusStore.swift
//  FocusKey
//
//  Persistence in the App Group, readable and writable from the app and its extensions.
//

import Foundation
import FamilyControls

nonisolated enum FocusStore {
    static let appGroupID = "group.com.example.FocusKey"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    enum Key {
        /// Single selection used before profiles existed; migrated into the first profile.
        static let legacySelection = "FocusKeySelection"
        static let profiles = "FocusKeyProfiles"
        static let activeProfile = "FocusKey.activeProfile"
        /// Manual lock (button / NFC / intents). Independent from schedules and limits.
        static let lockState = "FocusKey.isLocked"
        static let manualProfile = "FocusKey.manualProfile"
        /// End of a timed session; absent for an indefinite manual lock.
        static let sessionEnd = "FocusKey.sessionEnd"
        /// Written by the monitor extension while a schedule interval is running.
        static let scheduleLockState = "FocusKey.isScheduleLocked"
        static let schedules = "FocusKeySchedules"
        /// [schedule UUID: end of the interval skipped with the NFC tag].
        static let scheduleSkips = "FocusKey.scheduleSkips"
        static let limits = "FocusKeyLimits"
        /// [limit UUID: moment it was reached]. Only counts on the same day.
        static let limitsReached = "FocusKey.limitsReached"
        /// [limit UUID: moment extra time was granted with the NFC tag]. Only counts on the same day.
        static let limitExtensions = "FocusKey.limitExtensions"
        /// Used by an earlier build, when the tag could lift limits. Removed on launch.
        static let legacyLimitSkips = "FocusKey.limitSkips"
        static let records = "FocusKey.blockRecords"
        /// Set by the "unlock with key" intent so the app starts an NFC scan when it opens.
        static let pendingNFCScan = "FocusKey.pendingNFCScan"
        /// Last error of an intent run from a widget or Control Center, shown by the app.
        static let lastIntentError = "FocusKey.lastIntentError"
    }

    // MARK: Profiles

    /// Saved profiles. The first call after updating migrates the old single selection.
    static func profiles() -> [FocusProfile] {
        if let data = defaults.data(forKey: Key.profiles),
           let saved = try? JSONDecoder().decode([FocusProfile].self, from: data),
           !saved.isEmpty {
            return saved
        }
        var selection = FamilyActivitySelection()
        if let data = defaults.data(forKey: Key.legacySelection),
           let legacy = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = legacy
        }
        let initial = [FocusProfile(name: "General", symbol: "lock.shield", selection: selection)]
        saveProfiles(initial)
        return initial
    }

    static func saveProfiles(_ profiles: [FocusProfile]) {
        save(profiles, forKey: Key.profiles)
    }

    /// The profile with this id, or the first one when `id` is nil or no longer exists.
    static func profile(_ id: UUID?, in profiles: [FocusProfile]? = nil) -> FocusProfile? {
        let all = profiles ?? self.profiles()
        return all.first { $0.id == id } ?? all.first
    }

    static var activeProfileID: UUID? {
        get { defaults.string(forKey: Key.activeProfile).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.activeProfile) }
    }

    // MARK: Manual lock

    static var isManualLocked: Bool {
        get { defaults.bool(forKey: Key.lockState) }
        set { defaults.set(newValue, forKey: Key.lockState) }
    }

    static var manualProfileID: UUID? {
        get { defaults.string(forKey: Key.manualProfile).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.manualProfile) }
    }

    static var sessionEnd: Date? {
        get { defaults.object(forKey: Key.sessionEnd) as? Date }
        set { defaults.set(newValue, forKey: Key.sessionEnd) }
    }

    // MARK: Schedules

    static func schedules() -> [FocusSchedule] {
        load([FocusSchedule].self, forKey: Key.schedules) ?? []
    }

    static func saveSchedules(_ schedules: [FocusSchedule]) {
        save(schedules, forKey: Key.schedules)
    }

    static func scheduleSkips() -> [String: Date] {
        defaults.dictionary(forKey: Key.scheduleSkips) as? [String: Date] ?? [:]
    }

    static func setScheduleSkips(_ skips: [String: Date]) {
        defaults.set(skips, forKey: Key.scheduleSkips)
    }

    static func isSkipped(_ schedule: FocusSchedule, at date: Date = .now) -> Bool {
        guard let until = scheduleSkips()[schedule.id.uuidString] else { return false }
        return until > date
    }

    // MARK: Usage limits

    static func limits() -> [UsageLimit] {
        load([UsageLimit].self, forKey: Key.limits) ?? []
    }

    static func saveLimits(_ limits: [UsageLimit]) {
        save(limits, forKey: Key.limits)
    }

    static func limitsReached() -> [String: Date] {
        defaults.dictionary(forKey: Key.limitsReached) as? [String: Date] ?? [:]
    }

    static func setLimitsReached(_ reached: [String: Date]) {
        defaults.set(reached, forKey: Key.limitsReached)
    }

    static func limitExtensions() -> [String: Date] {
        defaults.dictionary(forKey: Key.limitExtensions) as? [String: Date] ?? [:]
    }

    static func setLimitExtensions(_ extensions: [String: Date]) {
        defaults.set(extensions, forKey: Key.limitExtensions)
    }

    static func isReachedToday(_ limit: UsageLimit, at date: Date = .now) -> Bool {
        guard limit.isEnabled, let reached = limitsReached()[limit.id.uuidString] else { return false }
        return Calendar.current.isDate(reached, inSameDayAs: date)
    }

    /// Reached today but with extra time granted with the tag that hasn't been used up.
    static func isExtended(_ limit: UsageLimit, at date: Date = .now) -> Bool {
        guard isReachedToday(limit, at: date), let granted = limitExtensions()[limit.id.uuidString] else { return false }
        return Calendar.current.isDate(granted, inSameDayAs: date)
    }

    /// Reached today and not extended: its apps are blocked until midnight.
    static func isBlocking(_ limit: UsageLimit, at date: Date = .now) -> Bool {
        isReachedToday(limit, at: date) && !isExtended(limit, at: date)
    }

    // MARK: Statistics

    private static let maxRecordAge: TimeInterval = 60 * 24 * 60 * 60

    static func records() -> [BlockRecord] {
        load([BlockRecord].self, forKey: Key.records) ?? []
    }

    static func openRecord(kind: BlockRecord.Kind, title: String, sourceID: String, at date: Date = .now) {
        var all = records()
        // Never keep two open records for the same source.
        guard !all.contains(where: { $0.sourceID == sourceID && $0.end == nil }) else { return }
        all.append(BlockRecord(kind: kind, title: title, sourceID: sourceID, start: date))
        saveRecords(all)
    }

    static func closeRecords(sourceID: String, at date: Date = .now) {
        var all = records()
        var changed = false
        for index in all.indices where all[index].sourceID == sourceID && all[index].end == nil {
            all[index].end = max(date, all[index].start)
            changed = true
        }
        if changed { saveRecords(all) }
    }

    private static func saveRecords(_ records: [BlockRecord]) {
        let cutoff = Date.now.addingTimeInterval(-maxRecordAge)
        save(records.filter { ($0.end ?? .now) > cutoff }, forKey: Key.records)
    }


    // MARK: Intents

    static func requestNFCScan() { defaults.set(true, forKey: Key.pendingNFCScan) }

    /// Returns true once after `requestNFCScan()`.
    static func consumeNFCScanRequest() -> Bool {
        guard defaults.bool(forKey: Key.pendingNFCScan) else { return false }
        defaults.set(false, forKey: Key.pendingNFCScan)
        return true
    }

    static var lastIntentError: String? {
        get { defaults.string(forKey: Key.lastIntentError) }
        set { defaults.set(newValue, forKey: Key.lastIntentError) }
    }

    // MARK: Helpers

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
