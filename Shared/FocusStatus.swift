//
//  FocusStatus.swift
//  FocusKey
//
//  Snapshot of everything that is blocking right now, for the app, widgets and shield screen.
//

import Foundation
import ManagedSettings

nonisolated struct FocusStatus {
    struct RunningSchedule {
        var schedule: FocusSchedule
        var profile: FocusProfile?
        var end: Date
    }

    struct ReachedLimit {
        var limit: UsageLimit
        var profile: FocusProfile?
    }

    var date: Date
    /// Profile locked manually (button, NFC, intent or session), if any.
    var manualProfile: FocusProfile?
    var isManualLocked: Bool
    var sessionEnd: Date?
    var sessionStart: Date?
    var schedules: [RunningSchedule]
    var limits: [ReachedLimit]

    var isBlocked: Bool { isManualLocked || !schedules.isEmpty || !limits.isEmpty }

    /// The NFC tag lifts the manual lock and schedules, not daily limits.
    var canUnlockWithKey: Bool { isManualLocked || !schedules.isEmpty }

    static func current(at date: Date = .now) -> FocusStatus {
        let profiles = FocusStore.profiles()
        let isManual = FocusStore.isManualLocked
        var sessionEnd = FocusStore.sessionEnd
        if let end = sessionEnd, end <= date { sessionEnd = nil }

        let schedules = FocusStore.schedules()
            .filter { $0.isActive(at: date) && !FocusStore.isSkipped($0, at: date) }
            .map { RunningSchedule(schedule: $0, profile: FocusStore.profile($0.profileID, in: profiles), end: $0.intervalEnd(after: date)) }

        let limits = FocusStore.limits()
            .filter { FocusStore.isBlocking($0, at: date) }
            .map { ReachedLimit(limit: $0, profile: FocusStore.profile($0.profileID, in: profiles)) }

        return FocusStatus(
            date: date,
            manualProfile: isManual ? FocusStore.profile(FocusStore.manualProfileID, in: profiles) : nil,
            isManualLocked: isManual,
            sessionEnd: isManual ? sessionEnd : nil,
            sessionStart: isManual && sessionEnd != nil ? FocusStore.sessionStart : nil,
            schedules: schedules,
            limits: limits
        )
    }

    /// Profile behind the current block (manual first, then schedules, then limits).
    var blockingProfile: FocusProfile? {
        if isManualLocked { return manualProfile }
        return schedules.first?.profile ?? limits.first?.profile
    }

    /// Fraction of the timed session already elapsed (0…1), or nil without a session.
    func sessionProgress(at date: Date) -> Double? {
        guard let start = sessionStart, let end = sessionEnd, end > start else { return nil }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    var headline: String {
        if isManualLocked { return sessionEnd == nil ? String(localized: "Bloqueado") : String(localized: "Sesión en curso") }
        if !schedules.isEmpty { return String(localized: "Bloqueado por horario") }
        if !limits.isEmpty { return String(localized: "Límite alcanzado") }
        return String(localized: "Desbloqueado")
    }

    /// One line describing why things are blocked.
    var detail: String? {
        if isManualLocked {
            let name = manualProfile?.displayName ?? String(localized: "Perfil")
            if let end = sessionEnd {
                return String(localized: "«\(name)» hasta las \(end.formatted(date: .omitted, time: .shortened))")
            }
            return String(localized: "«\(name)» hasta que uses tu llave")
        }
        if let first = schedules.first {
            return String(localized: "«\(first.schedule.displayName)» hasta las \(first.end.formatted(date: .omitted, time: .shortened))")
        }
        if let first = limits.first {
            return String(localized: "«\(first.limit.displayName)» hasta medianoche")
        }
        return nil
    }

    /// Next moment the status changes on its own (session end or schedule end).
    var nextChange: Date? {
        ([sessionEnd].compactMap { $0 } + schedules.map(\.end)).min()
    }

    // MARK: Shield reasons

    /// Profile whose block covers this item (manual, then schedules, then limits).
    func profile(matching contains: (FocusProfile) -> Bool) -> FocusProfile? {
        if isManualLocked, let profile = manualProfile, contains(profile) { return profile }
        if let running = schedules.first(where: { $0.profile.map(contains) ?? false }) { return running.profile }
        return limits.first(where: { $0.profile.map(contains) ?? false })?.profile
    }

    /// Explanation for the shield screen, picking the source that blocks this item.
    func reason(matching contains: (FocusProfile) -> Bool) -> String {
        if isManualLocked, let profile = manualProfile, contains(profile) {
            if let end = sessionEnd {
                return String(localized: "Sesión de concentración hasta las \(end.formatted(date: .omitted, time: .shortened)).")
            }
            return String(localized: "Acerca tu llave FocusKey al iPhone para desbloquear.")
        }
        if let running = schedules.first(where: { $0.profile.map(contains) ?? false }) {
            return String(localized: "Horario «\(running.schedule.displayName)» hasta las \(running.end.formatted(date: .omitted, time: .shortened)).")
        }
        if let reached = limits.first(where: { $0.profile.map(contains) ?? false }) {
            return "Has usado tus \(UsageLimit.formatted(minutes: reached.limit.minutes)) de hoy. Se desbloquea a medianoche, o amplíalo con tu llave en FocusKey."
        }
        return "Esta app está bloqueada por FocusKey."
    }
}
