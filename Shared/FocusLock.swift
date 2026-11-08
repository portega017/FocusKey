//
//  FocusLock.swift
//  FocusKey
//
//  Applies and lifts shields. Used by the app, the monitor extension, the widgets and App Intents.
//  Every blocking source has its own named store; iOS combines the shields of all stores.
//

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import WidgetKit

nonisolated enum FocusLock {
    static let manualStoreName = ManagedSettingsStore.Name("FocusKey.manual")
    static let scheduleStoreName = ManagedSettingsStore.Name("FocusKey.schedule")
    static let limitStoreName = ManagedSettingsStore.Name("FocusKey.limit")

    /// DeviceActivity rejects intervals shorter than 15 minutes.
    static let minimumSessionMinutes = 15
    static let manualSourceID = "manual"

    enum LockError: LocalizedError {
        case notAuthorized
        case emptyProfile(String)
        case alreadyLocked
        case sessionTooShort
        case monitoring(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return String(localized: "Autoriza Screen Time en FocusKey antes de bloquear.")
            case .emptyProfile(let name):
                return String(localized: "El perfil «\(name)» no tiene apps, categorías ni webs seleccionadas.")
            case .alreadyLocked:
                return String(localized: "El bloqueo ya está activo.")
            case .sessionTooShort:
                return String(localized: "Una sesión debe durar al menos \(FocusLock.minimumSessionMinutes) minutos.")
            case .monitoring(let error):
                return String(localized: "No se pudo programar el final de la sesión: \(error.localizedDescription)")
            }
        }
    }

    static var isAuthorized: Bool {
        let status = AuthorizationCenter.shared.authorizationStatus
        return status == .approved || status == .approvedWithDataAccess
    }

    // MARK: Manual lock and timed sessions

    /// Blocks a profile until unlocked with the tag, or for `minutes` when given.
    @discardableResult
    static func lockManually(profileID: UUID?, minutes: Int? = nil, now: Date = .now) throws(LockError) -> FocusProfile {
        guard isAuthorized else { throw .notAuthorized }
        guard !FocusStore.isManualLocked else { throw .alreadyLocked }
        guard let profile = FocusStore.profile(profileID) else { throw .emptyProfile("") }
        guard !profile.isEmpty else { throw .emptyProfile(profile.displayName) }

        var sessionEnd: Date?
        if let minutes {
            guard minutes >= minimumSessionMinutes else { throw .sessionTooShort }
            let end = now.addingTimeInterval(TimeInterval(minutes * 60))
            let calendar = Calendar.current
            let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(parts, from: now),
                intervalEnd: calendar.dateComponents(parts, from: end),
                repeats: false
            )
            do {
                // The monitor extension lifts the lock when this interval ends.
                try DeviceActivityCenter().startMonitoring(FocusActivity.session, during: schedule)
            } catch {
                throw .monitoring(error)
            }
            sessionEnd = end
        }

        apply(profile.selection, to: ManagedSettingsStore(named: manualStoreName))
        FocusStore.isManualLocked = true
        FocusStore.manualProfileID = profile.id
        FocusStore.sessionEnd = sessionEnd
        FocusStore.openRecord(
            kind: sessionEnd == nil ? .manual : .session,
            title: profile.displayName,
            sourceID: manualSourceID,
            at: now
        )
        reloadWidgets()
        return profile
    }

    static func clearManualLock(at date: Date = .now) {
        DeviceActivityCenter().stopMonitoring([FocusActivity.session])
        ManagedSettingsStore(named: manualStoreName).clearAllSettings()
        // Store used by the first versions of the app.
        ManagedSettingsStore().clearAllSettings()
        FocusStore.isManualLocked = false
        FocusStore.manualProfileID = nil
        FocusStore.sessionEnd = nil
        FocusStore.closeRecords(sourceID: manualSourceID, at: date)
        reloadWidgets()
    }

    /// Fallback in case the monitor didn't get to end a finished session.
    static func expireSessionIfNeeded(now: Date = .now) {
        guard FocusStore.isManualLocked, let end = FocusStore.sessionEnd, end <= now else { return }
        clearManualLock(at: end)
    }

    // MARK: NFC master key

    struct KeyUnlockResult {
        var manual = false
        var schedules: [FocusSchedule] = []

        var isEmpty: Bool { !manual && schedules.isEmpty }
    }

    /// Lifts the manual lock and running schedules (until their interval ends).
    /// Reached daily limits are not affected: they last until midnight.
    @discardableResult
    static func unlockWithKey(now: Date = .now) -> KeyUnlockResult {
        var result = KeyUnlockResult()

        let running = FocusStore.schedules().filter { $0.isActive(at: now) && !FocusStore.isSkipped($0, at: now) }
        if !running.isEmpty {
            var skips = FocusStore.scheduleSkips().filter { $0.value > now }
            for schedule in running {
                skips[schedule.id.uuidString] = schedule.intervalEnd(after: now)
                FocusStore.closeRecords(sourceID: schedule.id.uuidString, at: now)
            }
            FocusStore.setScheduleSkips(skips)
            refreshScheduleShield(now: now)
            result.schedules = running
        }

        if FocusStore.isManualLocked {
            clearManualLock(at: now)
            result.manual = true
        }

        reloadWidgets()
        return result
    }

    // MARK: Schedules (monitor extension and NFC)

    /// Shields the union of profiles of every running, non-skipped schedule.
    /// `starting` is counted as running even if the clock is a few seconds early;
    /// `ending` is excluded even if the clock is a few seconds late.
    @discardableResult
    static func refreshScheduleShield(starting: UUID? = nil, ending: UUID? = nil, now: Date = .now) -> [FocusSchedule] {
        let profiles = FocusStore.profiles()
        let running = FocusStore.schedules().filter { schedule in
            guard schedule.isEnabled, schedule.id != ending, !FocusStore.isSkipped(schedule, at: now) else {
                return false
            }
            if schedule.id == starting {
                return schedule.repeats.contains(.of(now))
            }
            return schedule.isActive(at: now)
        }

        let store = ManagedSettingsStore(named: scheduleStoreName)
        let selections = running.compactMap { FocusStore.profile($0.profileID, in: profiles)?.selection }
        if let selection = union(selections) {
            apply(selection, to: store)
            FocusStore.defaults.set(true, forKey: FocusStore.Key.scheduleLockState)
        } else {
            store.clearAllSettings()
            FocusStore.defaults.set(false, forKey: FocusStore.Key.scheduleLockState)
        }
        return running
    }

    // MARK: Usage limits (monitor extension and NFC)

    /// Shields the union of profiles of every limit reached today and not skipped.
    static func refreshLimitShield(now: Date = .now) {
        let profiles = FocusStore.profiles()
        let blocking = FocusStore.limits().filter { FocusStore.isBlocking($0, at: now) }
        let selections = blocking.compactMap { FocusStore.profile($0.profileID, in: profiles)?.selection }
        let store = ManagedSettingsStore(named: limitStoreName)
        if let selection = union(selections) {
            apply(selection, to: store)
        } else {
            store.clearAllSettings()
        }
    }

    /// Grants `minutes` of extra use to every blocking limit (after a valid NFC tag).
    /// The monitor blocks them again when the extra time has been used.
    @discardableResult
    static func extendReachedLimits(minutes: Int, now: Date = .now) -> [UsageLimit] {
        let profiles = FocusStore.profiles()
        let blocking = FocusStore.limits().filter { FocusStore.isBlocking($0, at: now) }
        guard !blocking.isEmpty else { return [] }

        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let endOfInterval = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        let center = DeviceActivityCenter()
        var extensions = FocusStore.limitExtensions()

        for limit in blocking {
            guard let selection = FocusStore.profile(limit.profileID, in: profiles)?.selection else { continue }
            let activity = FocusActivity.extra(limit.id)
            center.stopMonitoring([activity])
            // Intervals under 15 minutes are rejected; that close to 23:59 the limit resets anyway.
            if endOfInterval.timeIntervalSince(now) >= 15 * 60 {
                try? center.startMonitoring(
                    activity,
                    during: DeviceActivitySchedule(
                        intervalStart: calendar.dateComponents(parts, from: now),
                        intervalEnd: calendar.dateComponents(parts, from: endOfInterval),
                        repeats: false
                    ),
                    events: [UsageLimit.extraEventName: UsageLimit.extraEvent(minutes: minutes, selection: selection)]
                )
            }
            extensions[limit.id.uuidString] = now
            FocusStore.closeRecords(sourceID: limit.id.uuidString, at: now)
        }
        FocusStore.setLimitExtensions(extensions)
        refreshLimitShield(now: now)
        reloadWidgets()
        return blocking
    }

    /// Extra time used up (or the day ended): the limit blocks again if still reached.
    static func endLimitExtension(_ id: UUID, now: Date = .now) {
        var extensions = FocusStore.limitExtensions()
        guard extensions.removeValue(forKey: id.uuidString) != nil else { return }
        FocusStore.setLimitExtensions(extensions)
        DeviceActivityCenter().stopMonitoring([FocusActivity.extra(id)])
        refreshLimitShield(now: now)
        if let limit = FocusStore.limits().first(where: { $0.id == id }), FocusStore.isBlocking(limit, at: now) {
            FocusStore.openRecord(kind: .limit, title: limit.displayName, sourceID: id.uuidString, at: now)
        }
        reloadWidgets()
    }

    // MARK: Helpers

    static func apply(_ selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        // Uninstalling FocusKey would lift every block. iOS only offers this for all apps at once.
        store.application.denyAppRemoval = FocusStore.preventAppRemoval ? true : nil
    }

    /// Re-applies every active shield after the "prevent app removal" setting changes.
    static func refreshAppRemovalProtection() {
        if FocusStore.isManualLocked, let profile = FocusStore.profile(FocusStore.manualProfileID) {
            apply(profile.selection, to: ManagedSettingsStore(named: manualStoreName))
        }
        refreshScheduleShield()
        refreshLimitShield()
    }

    /// Combined selection, or nil when there is nothing to block.
    static func union(_ selections: [FamilyActivitySelection]) -> FamilyActivitySelection? {
        var result = FamilyActivitySelection()
        for selection in selections {
            result.applicationTokens.formUnion(selection.applicationTokens)
            result.categoryTokens.formUnion(selection.categoryTokens)
            result.webDomainTokens.formUnion(selection.webDomainTokens)
        }
        let isEmpty = result.applicationTokens.isEmpty && result.categoryTokens.isEmpty && result.webDomainTokens.isEmpty
        return isEmpty ? nil : result
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
