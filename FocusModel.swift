//
//  FocusModel.swift
//  FocusKey
//
//  App state: profiles, manual lock and sessions, schedules, usage limits and statistics.
//  Shield logic shared with the extensions lives in Shared/FocusLock.swift.
//

import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications
import WidgetKit
import AppIntents

@MainActor
final class FocusModel: ObservableObject {
    typealias Schedule = FocusSchedule
    typealias Weekday = FocusWeekday

    // MARK: - Published state

    @Published private(set) var profiles: [FocusProfile] = []
    /// Profile used by the lock button, widgets and intents without a profile.
    @Published var activeProfileID: UUID? {
        didSet { FocusStore.activeProfileID = activeProfileID }
    }
    @Published private(set) var isLocked = false
    @Published private(set) var manualProfileID: UUID?
    @Published private(set) var sessionEnd: Date?
    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var presets: [SessionPreset] = []
    @Published private(set) var limits: [UsageLimit] = []
    @Published private(set) var records: [BlockRecord] = []
    /// Per-day minutes of days whose records were pruned (yearly statistics).
    @Published private(set) var dailyArchive: [String: Int] = [:]
    @Published private(set) var archivedUntil: Date?
    @Published private(set) var pomodoro: PomodoroPlan?
    /// Moments the Screen Time permission was found revoked (last 60 days).
    @Published private(set) var revocations: [Date] = []
    @Published private(set) var isAuthorized = FocusLock.isAuthorized
    /// Last message for the user, shown as a toast. Every assignment shows it again, even if
    /// the text is the same (`statusID` changes).
    @Published var status = String(localized: "Autoriza Screen Time para empezar.") {
        didSet { statusID = UUID() }
    }
    @Published private(set) var statusID: UUID?
    @Published private(set) var preventAppRemoval = FocusStore.preventAppRemoval
    @Published private(set) var strictMode = FocusStore.strictMode
    /// Live Activity on the Lock Screen and Dynamic Island for sessions and pomodoros.
    @Published var liveActivities = FocusStore.liveActivities {
        didSet {
            guard liveActivities != oldValue else { return }
            FocusStore.liveActivities = liveActivities
            Task { await FocusLiveActivity.sync() }
        }
    }
    @Published var limitWarnings = FocusStore.limitWarnings {
        didSet {
            FocusStore.limitWarnings = limitWarnings
            if limitWarnings { requestNotificationPermission() }
        }
    }

    private let deviceActivityCenter = DeviceActivityCenter()

    /// Set by the root view: scans the NFC tag and runs the action if it's valid.
    var requestKey: ((_ message: String, _ action: @escaping () -> Void) -> Void)?
    /// True while running an action the tag has just confirmed.
    private var keyConfirmed = false

    init() {
        reload()
        startMonitoringForEnabledSchedules()
        startMonitoringForEnabledLimits()
    }

    var activeProfile: FocusProfile? { FocusStore.profile(activeProfileID, in: profiles) }

    func profile(_ id: UUID?) -> FocusProfile? { FocusStore.profile(id, in: profiles) }

    // MARK: - Sync with the App Group

    /// Reloads everything the extensions, widgets or intents may have changed.
    func reload() {
        FocusLock.expireSessionIfNeeded()
        // Limits skipped with the tag by an earlier build: re-apply them.
        if FocusStore.defaults.object(forKey: FocusStore.Key.legacyLimitSkips) != nil {
            FocusStore.defaults.removeObject(forKey: FocusStore.Key.legacyLimitSkips)
            FocusLock.refreshLimitShield()
            for limit in FocusStore.limits() where FocusStore.isBlocking(limit) {
                FocusStore.openRecord(kind: .limit, title: limit.displayName, sourceID: limit.id.uuidString)
            }
        }
        profiles = FocusStore.profiles()
        let savedActive = FocusStore.activeProfileID
        activeProfileID = profiles.contains { $0.id == savedActive } ? savedActive : profiles.first?.id
        isLocked = FocusStore.isManualLocked
        manualProfileID = FocusStore.manualProfileID
        sessionEnd = FocusStore.sessionEnd
        schedules = FocusStore.schedules()
        presets = FocusStore.presets()
        limits = FocusStore.limits()
        records = FocusStore.records()
        dailyArchive = FocusStore.dailyArchive()
        archivedUntil = FocusStore.archivedUntil
        pomodoro = FocusStore.activePomodoro()
        revocations = FocusStore.revocations()
        isAuthorized = FocusLock.isAuthorized
        Task { await FocusLiveActivity.sync() }
    }

    /// Called when the app becomes active.
    func refreshFromStorage() {
        reload()
        if let error = FocusStore.lastIntentError {
            status = String(localized: "No se pudo bloquear automáticamente: \(error)")
            FocusStore.lastIntentError = nil
        }
        startMonitoringForEnabledSchedules()
        startMonitoringForEnabledLimits()
        // The status can lag right after launch: check again a moment later before logging a revocation.
        Task {
            try? await Task.sleep(for: .seconds(1))
            checkAuthorization()
        }
    }

    // MARK: - Strict mode

    /// In strict mode, a weakening change waits for the NFC tag and then runs `action` again.
    /// Returns true when the change was held back.
    private func needsKey(_ weakening: Bool, retry action: @escaping () -> Void) -> Bool {
        guard strictMode, weakening, !keyConfirmed else { return false }
        let message = String(localized: "Modo estricto: acerca tu llave para confirmar el cambio.")
        status = message
        guard let requestKey else { return true }
        requestKey(message) { [weak self] in
            guard let self else { return }
            keyConfirmed = true
            action()
            keyConfirmed = false
        }
        return true
    }

    /// Turning strict mode on is free; turning it off needs the tag.
    func setStrictMode(_ enabled: Bool) {
        guard enabled != strictMode else { return }
        if needsKey(!enabled, retry: { self.setStrictMode(enabled) }) { return }
        strictMode = enabled
        FocusStore.strictMode = enabled
        status = enabled
            ? String(localized: "Modo estricto activado: para relajar un bloqueo necesitarás tu llave.")
            : String(localized: "Modo estricto desactivado.")
    }

    func setPreventAppRemoval(_ enabled: Bool) {
        guard enabled != preventAppRemoval else { return }
        if needsKey(!enabled, retry: { self.setPreventAppRemoval(enabled) }) { return }
        preventAppRemoval = enabled
        FocusStore.preventAppRemoval = enabled
        FocusLock.reapplyAllShields()
    }

    // MARK: - Authorization

    func authorize() async {
        let center = AuthorizationCenter.shared

        switch center.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            break
        case .notDetermined, .denied:
            do {
                try await center.requestAuthorization(for: .individual)
                // Right after launch iOS can briefly report "not determined" and the request then
                // succeeds silently: only speak up when it really isn't approved.
                if !FocusLock.isAuthorized {
                    status = String(localized: "La autorización no está aprobada.")
                }
            } catch {
                status = String(localized: "Error de autorización: \(error.localizedDescription)")
            }
        @unknown default:
            status = String(localized: "Estado de autorización desconocido.")
        }
        checkAuthorization()
    }

    /// Notices when the Screen Time permission was revoked (Settings › Screen Time), which lifts
    /// every block, and restores all blocks once it is granted again.
    func checkAuthorization() {
        if FocusLock.isAuthorized {
            if !FocusStore.wasAuthorized {
                FocusStore.wasAuthorized = true
                if !FocusStore.revocations().isEmpty {
                    FocusLock.reapplyAllShields()
                    startMonitoringForEnabledSchedules()
                    startMonitoringForEnabledLimits()
                }
            }
        } else if FocusStore.wasAuthorized {
            FocusStore.wasAuthorized = false
            FocusStore.logRevocation()
            status = String(localized: "Se ha retirado el permiso de Screen Time: ningún bloqueo funciona hasta que lo vuelvas a autorizar.")
        }
        isAuthorized = FocusLock.isAuthorized
        revocations = FocusStore.revocations()
    }

    /// Revoked and not granted again yet.
    var isAuthorizationRevoked: Bool { !isAuthorized && !revocations.isEmpty }

    // MARK: - Manual lock and sessions

    /// Locks a profile (the active one by default), indefinitely or for `minutes`.
    func lock(minutes: Int? = nil, profileID: UUID? = nil) {
        do {
            let profile = try FocusLock.lockManually(profileID: profileID ?? activeProfileID, minutes: minutes)
            if let minutes {
                status = String(localized: "«\(profile.displayName)» bloqueado durante \(UsageLimit.formatted(minutes: minutes)).")
            } else {
                status = String(localized: "«\(profile.displayName)» bloqueado.")
            }
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    /// The tag lifts the manual lock and running schedules; if neither is active it locks
    /// the active profile. Daily limits are never lifted by the tag.
    func handleNFC() {
        guard FocusStatus.current().canUnlockWithKey else {
            lock()
            return
        }
        let result = FocusLock.unlockWithKey()
        var parts: [String] = []
        if result.pomodoro {
            parts.append(String(localized: "pomodoro terminado"))
            PomodoroNotifications.cancel()
        }
        if result.manual { parts.append(String(localized: "bloqueo manual desactivado")) }
        if !result.schedules.isEmpty { parts.append(String(localized: "horario desbloqueado hasta el final del intervalo")) }
        if !FocusStatus.current().limits.isEmpty { parts.append(String(localized: "los límites alcanzados siguen activos hasta medianoche")) }
        status = parts.isEmpty ? String(localized: "No había nada bloqueado.") : parts.joined(separator: ", ").capitalizedFirst + "."
        reload()
    }

    /// Called after a valid tag when the user asked for extra time on reached limits.
    func extendLimits(minutes: Int) {
        let extended = FocusLock.extendReachedLimits(minutes: minutes)
        status = extended.isEmpty
            ? String(localized: "No hay ningún límite alcanzado.")
            : String(localized: "Tienes \(UsageLimit.formatted(minutes: minutes)) más. Después se volverá a bloquear.")
        reload()
    }

    /// Adds time to the running timed session (no key: it only makes it stricter).
    func extendSession(minutes: Int) {
        do {
            let end = try FocusLock.extendSession(minutes: minutes)
            status = String(localized: "Sesión alargada hasta las \(end.formatted(date: .omitted, time: .shortened)).")
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    /// Ends the current pomodoro break and starts the next focus block now.
    func skipPomodoroBreak() {
        guard let plan = FocusLock.skipPomodoroBreak() else { return }
        PomodoroNotifications.schedule(plan)
        status = String(localized: "Descanso saltado: a concentrarse.")
        reload()
    }

    // MARK: - Session presets

    func startPreset(_ preset: SessionPreset) {
        if let pomodoro = preset.pomodoro {
            startPomodoro(focusMinutes: pomodoro.focusMinutes, breakMinutes: pomodoro.breakMinutes,
                          cycles: pomodoro.cycles, profileID: preset.profileID)
        } else {
            lock(minutes: preset.minutes, profileID: preset.profileID)
        }
    }

    func addPreset(_ preset: SessionPreset) {
        presets.append(preset)
        savePresets()
    }

    func updatePreset(_ preset: SessionPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        savePresets()
    }

    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        savePresets()
    }

    private func savePresets() {
        FocusStore.savePresets(presets)
        // Siri phrases use preset names as parameter values.
        FocusShortcuts.updateAppShortcutParameters()
        // The medium widget and the Control Center button show presets.
        FocusLock.reloadWidgets()
    }

    // MARK: - Pomodoro

    /// Starts a pomodoro on a profile (the active one by default).
    func startPomodoro(focusMinutes: Int, breakMinutes: Int, cycles: Int, profileID: UUID? = nil) {
        do {
            let plan = try FocusLock.startPomodoro(
                profileID: profileID ?? activeProfileID, focusMinutes: focusMinutes, breakMinutes: breakMinutes, cycles: cycles
            )
            PomodoroNotifications.schedule(plan)
            status = String(localized: "Pomodoro iniciado: \(plan.cycles) ciclos, termina a las \(plan.end.formatted(date: .omitted, time: .shortened)).")
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    func isLimitExtended(_ limit: UsageLimit, at date: Date = .now) -> Bool {
        FocusStore.isExtended(limit, at: date)
    }

    func isBlocked(at date: Date = .now) -> Bool {
        FocusStatus.current(at: date).isBlocked
    }

    // MARK: - Profiles

    @discardableResult
    func addProfile(_ profile: FocusProfile) -> Bool {
        profiles.append(profile)
        FocusStore.saveProfiles(profiles)
        status = String(localized: "Perfil «\(profile.displayName)» creado.")
        return true
    }

    func updateProfile(_ profile: FocusProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let existing = profiles[index]
        // Changing the apps of a profile that is blocking now would let you lift the block.
        if existing.selection != profile.selection, let reason = profileLockReason(profile.id) {
            status = reason
            return
        }
        if needsKey(existing.isWeakened(by: profile), retry: { self.updateProfile(profile) }) { return }
        profiles[index] = profile
        FocusStore.saveProfiles(profiles)
        // Preset titles shown to Siri include the profile name.
        if existing.name != profile.name { FocusShortcuts.updateAppShortcutParameters() }

        if existing.selection != profile.selection {
            // Limits register their apps with iOS: register them again with the new apps.
            for limit in limits where limit.isEnabled && profileID(of: limit) == profile.id {
                startMonitoring(limit)
            }
        }
        FocusLock.reloadWidgets()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else {
            status = String(localized: "Necesitas al menos un perfil.")
            return
        }
        if let reason = profileLockReason(id) {
            status = reason
            return
        }
        let usedBySchedule = schedules.contains { profileID(of: $0) == id }
        let usedByLimit = limits.contains { profileID(of: $0) == id }
        guard !usedBySchedule, !usedByLimit else {
            status = String(localized: "Este perfil lo usan horarios o límites. Cámbialos antes de eliminarlo.")
            return
        }
        profiles.removeAll { $0.id == id }
        FocusStore.saveProfiles(profiles)
        if activeProfileID == id { activeProfileID = profiles.first?.id }
        // A "1 h of Social" preset makes no sense with another profile: remove it.
        if presets.contains(where: { $0.profileID == id }) {
            presets.removeAll { $0.profileID == id }
            savePresets()
        }
        FocusLock.reloadWidgets()
    }

    /// Why the profile's apps can't be changed right now, or nil if they can.
    func profileLockReason(_ id: UUID, at date: Date = .now) -> String? {
        let status = FocusStatus.current(at: date)
        if status.isManualLocked, status.manualProfile?.id == id {
            return String(localized: "Este perfil está bloqueado ahora. Desbloquéalo con tu llave para cambiar sus apps.")
        }
        if status.schedules.contains(where: { $0.profile?.id == id }) {
            return String(localized: "Un horario en curso usa este perfil. Podrás cambiar sus apps cuando termine.")
        }
        if status.pomodoro?.profileID == id {
            return String(localized: "Un pomodoro en curso usa este perfil. Podrás cambiar sus apps cuando termine.")
        }
        if status.limits.contains(where: { $0.profile?.id == id }) {
            return String(localized: "Un límite alcanzado hoy usa este perfil. Podrás cambiar sus apps mañana.")
        }
        return nil
    }

    /// Resolves a missing or deleted profile to the first one, like the extensions do.
    func profileID(of schedule: Schedule) -> UUID? { profile(schedule.profileID)?.id }
    func profileID(of limit: UsageLimit) -> UUID? { profile(limit.profileID)?.id }

    // MARK: - Schedules

    func isScheduleActive(_ schedule: Schedule, at date: Date = .now) -> Bool {
        schedule.isActive(at: date)
    }

    func isScheduleSkipped(_ schedule: Schedule, at date: Date = .now) -> Bool {
        FocusStore.isSkipped(schedule, at: date)
    }

    func addSchedule(_ schedule: Schedule) {
        schedules.append(schedule)
        FocusStore.saveSchedules(schedules)
        if schedule.isEnabled { startMonitoring(schedule) }
        FocusLock.reloadWidgets()
    }

    func updateSchedule(_ schedule: Schedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        let existing = schedules[index]
        // A running schedule can't be changed at all: any change re-registers it with iOS,
        // which ends the current interval and lifts the block.
        guard existing == schedule || !existing.isActive() else {
            status = String(localized: "No puedes modificar un horario mientras está en curso.")
            return
        }
        if needsKey(existing.isWeakened(by: schedule), retry: { self.updateSchedule(schedule) }) { return }
        schedules[index] = schedule
        FocusStore.saveSchedules(schedules)
        if schedule.isEnabled {
            startMonitoring(schedule)
        } else {
            deviceActivityCenter.stopMonitoring([schedule.activityName])
        }
        FocusLock.reloadWidgets()
    }

    func deleteSchedule(_ id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        guard !schedule.isActive() else {
            status = String(localized: "No puedes eliminar un horario mientras el bloqueo está activo.")
            return
        }
        if needsKey(schedule.isEnabled, retry: { self.deleteSchedule(id) }) { return }
        schedules.removeAll { $0.id == id }
        FocusStore.saveSchedules(schedules)
        deviceActivityCenter.stopMonitoring([schedule.activityName])
        FocusLock.reloadWidgets()
    }

    func duplicateSchedule(_ id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        addSchedule(Schedule(
            name: schedule.name.isEmpty ? "" : String(localized: "\(schedule.name) (copia)"),
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            repeats: schedule.repeats,
            isEnabled: schedule.isEnabled,
            profileID: schedule.profileID
        ))
    }

    /// Skips the interval that starts on `day` (needs the tag in strict mode).
    /// iOS still calls the monitor that day; it sees the pause and doesn't block.
    func pauseSchedule(_ id: UUID, on day: Date) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        var schedule = schedules[index]
        guard schedule.intervalStart(on: day) > .now else {
            status = String(localized: "Ese día el horario ya ha empezado. Usa tu llave para desbloquearlo.")
            return
        }
        guard !schedule.isPaused(on: day) else { return }
        if needsKey(schedule.isEnabled, retry: { self.pauseSchedule(id, on: day) }) { return }
        schedule.pausedDays = (schedule.prunedPauses() + [Calendar.current.startOfDay(for: day)]).sorted()
        schedules[index] = schedule
        // Saved without re-registering with iOS: a pause doesn't change the interval.
        FocusStore.saveSchedules(schedules)
        status = String(localized: "«\(schedule.displayName)» no se activará el \(day.formatted(.dateTime.weekday(.wide).day().month())).")
        FocusLock.reloadWidgets()
    }

    /// Cancels a pause. No key needed: it only makes things stricter.
    func resumeSchedule(_ id: UUID, on day: Date) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        var schedule = schedules[index]
        schedule.pausedDays = schedule.prunedPauses().filter { !Calendar.current.isDate($0, inSameDayAs: day) }
        schedules[index] = schedule
        FocusStore.saveSchedules(schedules)
        // If that interval is running right now, block straight away.
        let running = FocusLock.refreshScheduleShield()
        if running.contains(where: { $0.id == id }) {
            FocusStore.openRecord(kind: .schedule, title: schedule.displayName, sourceID: id.uuidString)
        }
        FocusLock.reloadWidgets()
        reload()
    }

    private func startMonitoring(_ schedule: Schedule) {
        deviceActivityCenter.stopMonitoring([schedule.activityName])
        guard let interval = schedule.deviceActivitySchedule else {
            status = String(localized: "Error al crear el horario «\(schedule.displayName)».")
            return
        }
        do {
            try deviceActivityCenter.startMonitoring(schedule.activityName, during: interval)
        } catch {
            status = String(localized: "Error al programar «\(schedule.displayName)»: \(error.localizedDescription)")
        }
    }

    /// Only registers schedules not already monitored: restarting an active one can make
    /// the system fire intervalDidEnd/intervalDidStart again.
    private func startMonitoringForEnabledSchedules() {
        for schedule in schedules where schedule.isEnabled {
            if let registered = deviceActivityCenter.schedule(for: schedule.activityName),
               let expected = schedule.deviceActivitySchedule,
               registered.intervalStart == expected.intervalStart,
               registered.intervalEnd == expected.intervalEnd {
                continue
            }
            startMonitoring(schedule)
        }
    }

    // MARK: - Usage limits

    func isLimitBlocking(_ limit: UsageLimit, at date: Date = .now) -> Bool {
        FocusStore.isBlocking(limit, at: date)
    }

    func addLimit(_ limit: UsageLimit) {
        if limitWarnings { requestNotificationPermission() }
        limits.append(limit)
        FocusStore.saveLimits(limits)
        if limit.isEnabled { startMonitoring(limit) }
        status = String(localized: "Límite «\(limit.displayName)» creado.")
    }

    func updateLimit(_ limit: UsageLimit) {
        guard let index = limits.firstIndex(where: { $0.id == limit.id }) else { return }
        guard !isLimitBlocking(limits[index]) else {
            status = String(localized: "Este límite ya se alcanzó hoy. Podrás cambiarlo mañana.")
            return
        }
        if needsKey(limits[index].isWeakened(by: limit), retry: { self.updateLimit(limit) }) { return }
        limits[index] = limit
        FocusStore.saveLimits(limits)
        if limit.isEnabled {
            startMonitoring(limit)
        } else {
            deviceActivityCenter.stopMonitoring([limit.activityName])
        }
    }

    func deleteLimit(_ id: UUID) {
        guard let limit = limits.first(where: { $0.id == id }) else { return }
        guard !isLimitBlocking(limit) else {
            status = String(localized: "Este límite ya se alcanzó hoy. Podrás eliminarlo mañana.")
            return
        }
        if needsKey(limit.isEnabled, retry: { self.deleteLimit(id) }) { return }
        limits.removeAll { $0.id == id }
        FocusStore.saveLimits(limits)
        deviceActivityCenter.stopMonitoring([limit.activityName, FocusActivity.extra(id)])
    }

    private func startMonitoring(_ limit: UsageLimit) {
        deviceActivityCenter.stopMonitoring([limit.activityName])
        guard let profile = profile(limit.profileID), !profile.isEmpty else {
            status = String(localized: "El perfil del límite «\(limit.displayName)» no tiene apps seleccionadas.")
            return
        }
        do {
            try deviceActivityCenter.startMonitoring(
                limit.activityName,
                during: UsageLimit.dailySchedule,
                events: limit.events(for: profile.selection)
            )
        } catch {
            status = String(localized: "Error al programar el límite «\(limit.displayName)»: \(error.localizedDescription)")
        }
    }

    private func startMonitoringForEnabledLimits() {
        let registered = Set(deviceActivityCenter.activities)
        for limit in limits where limit.isEnabled {
            if !registered.contains(limit.activityName) {
                startMonitoring(limit)
            } else if limit.warningLeadMinutes != nil,
                      deviceActivityCenter.events(for: limit.activityName)[UsageLimit.warningEventName] == nil,
                      !FocusStore.isReachedToday(limit) {
                // Registered by an older build without the warning event.
                startMonitoring(limit)
            }
        }
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
