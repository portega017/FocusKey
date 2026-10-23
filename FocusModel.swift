//
//  FocusModel.swift
//  FocusKey
//
//  Created by pibol on 14/10/2026.
//  Updated to support multiple schedules.
//

import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class FocusModel: ObservableObject {

    // MARK: - App Group Shared Defaults
    static let appGroupID = "group.com.example.FocusKey"
    static let sharedDefaults = UserDefaults(suiteName: appGroupID)!
    static let selectionKey = "FocusKeySelection"
    static let lockStateKey = "FocusKey.isLocked"
    static let schedulesKey = "FocusKeySchedules"

    // MARK: - Published Properties
    @Published var selection = FamilyControls.FamilyActivitySelection() {
        didSet {
            if let data = try? JSONEncoder().encode(selection) {
                Self.sharedDefaults.set(data, forKey: Self.selectionKey)
            }
        }
    }

    @Published var isLocked: Bool = false {
        didSet {
            Self.sharedDefaults.set(isLocked, forKey: Self.lockStateKey)
        }
    }

    @Published var status = "Autoriza Screen Time para empezar."

    // MARK: - Schedules
    @Published private(set) var schedules: [Schedule] = [] {
        didSet { saveSchedules() }
    }

    // MARK: - Private Properties
    private let store = ManagedSettingsStore()
    private let deviceActivityCenter = DeviceActivityCenter()

    // MARK: - Initialization
    init() {
        loadSelection()
        loadLockState()
        loadSchedules()
        // Start monitoring for enabled schedules on launch
        startMonitoringForEnabledSchedules()
    }

    // MARK: - Public Methods

    func authorize() async {
        let center = AuthorizationCenter.shared

        switch center.authorizationStatus {
        case .approved:
            status = "Screen Time ya está autorizado."
        case .approvedWithDataAccess:
            status = "Screen Time ya está autorizado con acceso a datos."
        case .notDetermined, .denied:
            do {
                try await center.requestAuthorization(for: .individual)

                if center.authorizationStatus == .approved {
                    status = "Autorización concedida."
                } else {
                    status = "La autorización no está aprobada."
                }
            } catch {
                status = "Error de autorización: \(error.localizedDescription)"
            }

        @unknown default:
            status = "Estado de autorización desconocido."
        }
    }

    func toggleLock() {
        setLock(!isLocked)
    }

    func handleNFC() {
        toggleLock()
    }

    // MARK: - Schedule Management

    /// Loads schedules from shared defaults.
    func loadSchedules() {
        if let data = Self.sharedDefaults.data(forKey: Self.schedulesKey),
           let saved = try? JSONDecoder().decode([Schedule].self, from: data) {
            schedules = saved
        }
    }

    /// Saves schedules to shared defaults.
    private func saveSchedules() {
        if let data = try? JSONEncoder().encode(schedules) {
            Self.sharedDefaults.set(data, forKey: Self.schedulesKey)
        }
    }

    /// Adds a new schedule.
    func addSchedule(_ schedule: Schedule) {
        schedules.append(schedule)
        if schedule.isEnabled {
            startMonitoring(for: schedule)
        }
    }

    /// Updates an existing schedule.
    func updateSchedule(_ schedule: Schedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            let existing = schedules[index]
            guard !(isScheduleActive(existing) && !schedule.isEnabled) else {
                status = "No puedes desactivar un horario mientras el bloqueo está activo."
                return
            }

            schedules[index] = schedule
            if schedule.isEnabled {
                startMonitoring(for: schedule)
            } else {
                stopMonitoring(for: schedule.id)
            }
        }
    }

    /// Deletes a schedule by its ID.
    func deleteSchedule(_ id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        guard !isScheduleActive(schedule) else {
            status = "No puedes eliminar un horario mientras el bloqueo está activo."
            return
        }

        schedules.removeAll { $0.id == id }
        stopMonitoring(for: id)
    }

    func duplicateSchedule(_ id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }

        let copyName = schedule.name.isEmpty ? "" : "\(schedule.name) (copia)"
        addSchedule(Schedule(
            name: copyName,
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            repeats: schedule.repeats,
            isEnabled: schedule.isEnabled
        ))
    }

    /// Toggles the enabled state of a schedule.
    func toggleScheduleEnabled(_ id: UUID) {
        if let index = schedules.firstIndex(where: { $0.id == id }) {
            schedules[index].isEnabled.toggle()
            if schedules[index].isEnabled {
                startMonitoring(for: schedules[index])
            } else {
                stopMonitoring(for: id)
            }
        }
    }

    // MARK: - Device Activity Monitoring

    /// Starts monitoring for a given schedule.
    private func startMonitoring(for schedule: Schedule) {
        // Stop any existing monitoring for this schedule ID
        stopMonitoring(for: schedule.id)

        // Create the DeviceActivitySchedule based on the schedule's time and repeats
        guard let deviceActivitySchedule = schedule.deviceActivitySchedule else {
            status = "Error al crear el horario para \(schedule.name)."
            return
        }

        // Unique activity name for this schedule
        let activityName = DeviceActivityName("FocusKeySchedule_\(schedule.id.uuidString)")

        do {
            try deviceActivityCenter.startMonitoring(activityName, during: deviceActivitySchedule)
        } catch {
            status = "Error al iniciar monitoreo para \(schedule.name): \(error.localizedDescription)"
        }
    }

    /// Stops monitoring for a schedule with the given ID.
    private func stopMonitoring(for id: UUID) {
        let activityName = DeviceActivityName("FocusKeySchedule_\(id.uuidString)")
        deviceActivityCenter.stopMonitoring([activityName])
    }

    /// Stops all monitoring tasks.
    private func stopAllMonitoring() {
        for id in schedules.map(\.id) {
            stopMonitoring(for: id)
        }
    }

    private func isScheduleActive(_ schedule: Schedule, at date: Date = .now) -> Bool {
        guard schedule.isEnabled else { return false }

        let calendar = Calendar.current
        let currentMinutes = minutes(from: date, calendar: calendar)
        let startMinutes = minutes(from: schedule.startTime, calendar: calendar)
        let endMinutes = minutes(from: schedule.endTime, calendar: calendar)

        if startMinutes < endMinutes {
            return schedule.repeats.contains(weekday(for: date, calendar: calendar))
                && currentMinutes >= startMinutes
                && currentMinutes < endMinutes
        }

        if currentMinutes >= startMinutes {
            return schedule.repeats.contains(weekday(for: date, calendar: calendar))
        }

        guard currentMinutes < endMinutes,
              let previousDate = calendar.date(byAdding: .day, value: -1, to: date) else {
            return false
        }
        return schedule.repeats.contains(weekday(for: previousDate, calendar: calendar))
    }

    private func weekday(for date: Date, calendar: Calendar) -> Weekday {
        Weekday.allCases.first {
            $0.calendarWeekday == calendar.component(.weekday, from: date)
        } ?? .sunday
    }

    private func minutes(from date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// Starts monitoring for all enabled schedules (called on launch).
    private func startMonitoringForEnabledSchedules() {
        for schedule in schedules where schedule.isEnabled {
            startMonitoring(for: schedule)
        }
    }

    // MARK: - Locking Helpers

    private func setLock(_ shouldLock: Bool, statusMessage: String? = nil) {
        let authStatus = AuthorizationCenter.shared.authorizationStatus
        guard authStatus == .approved || authStatus == .approvedWithDataAccess else {
            status = "Error: autorización de Screen Time no aprobada."
            return
        }

        if shouldLock {
            let applicationsToBlock: Set<ManagedSettings.ApplicationToken> = selection.applicationTokens
            let categoriesToBlock: Set<ManagedSettings.ActivityCategoryToken> = selection.categoryTokens
            let webDomainsToBlock: Set<ManagedSettings.WebDomainToken> = selection.webDomainTokens

            guard !applicationsToBlock.isEmpty || !categoriesToBlock.isEmpty || !webDomainsToBlock.isEmpty else {
                status = "Selecciona aplicaciones, categorías o dominios web para bloquear."
                return
            }

            guard !isLocked else {
                status = statusMessage ?? "El bloqueo ya está activo."
                return
            }

            store.shield.applications = applicationsToBlock
            store.shield.applicationCategories = .specific(categoriesToBlock)
            store.shield.webDomains = webDomainsToBlock

            isLocked = true
            status = statusMessage ?? "Bloqueo activado."
        } else {
            guard isLocked else {
                status = statusMessage ?? "El bloqueo ya está desactivado."
                return
            }

            store.clearAllSettings()
            isLocked = false
            status = statusMessage ?? "Bloqueo desactivado."
        }
    }

    private func applyScheduledLock(withScheduleName scheduleName: String? = nil) async {
        let message = scheduleName.map { "Bloqueo programado activado (\($0))." } ?? "Bloqueo programado activado."
        await MainActor.run {
            setLock(true, statusMessage: message)
        }
    }

    private func clearScheduledLock(withScheduleName scheduleName: String? = nil) async {
        let message = scheduleName.map { "Bloqueo programado desactivado (\($0))." } ?? "Bloqueo programado desactivado."
        await MainActor.run {
            setLock(false, statusMessage: message)
        }
    }

    // MARK: - Selection Persistence

    func loadSelection() {
        if let data = Self.sharedDefaults.data(forKey: Self.selectionKey),
           let saved = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: data) {
            selection = saved
        }
    }

    func loadLockState() {
        isLocked = Self.sharedDefaults.bool(forKey: Self.lockStateKey)
    }

    // MARK: - Formatting

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Reloads the selection and lock state from shared defaults.
    func refreshPersistedState() {
        loadSelection()
        loadLockState()
    }

    /// Reloads the schedules from shared defaults and starts monitoring for enabled ones.
    func syncScheduledMonitoringFromStorage() {
        loadSchedules()
        startMonitoringForEnabledSchedules()
    }

    // MARK: - Schedule Struct

    /// Represents a weekly interval during which the selected content is blocked.
    struct Schedule: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var startTime: Date
        var endTime: Date
        var repeats: Set<Weekday>
        var isEnabled: Bool

        init(
            id: UUID = UUID(),
            name: String = "",
            startTime: Date,
            endTime: Date,
            repeats: Set<Weekday>,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.name = name
            self.startTime = startTime
            self.endTime = endTime
            self.repeats = repeats
            self.isEnabled = isEnabled
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, startTime, endTime, time, repeats, isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
                ?? container.decode(Date.self, forKey: .time)
            endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
                ?? Calendar.current.date(byAdding: .minute, value: 15, to: startTime)!
            repeats = try container.decode(Set<Weekday>.self, forKey: .repeats)
            isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(endTime, forKey: .endTime)
            try container.encode(repeats, forKey: .repeats)
            try container.encode(isEnabled, forKey: .isEnabled)
        }

        /// Computes the daily monitor interval. The extension filters callbacks by weekday.
        var deviceActivitySchedule: DeviceActivitySchedule? {
            guard !repeats.isEmpty else { return nil }

            let calendar = Calendar.current
            let start = calendar.dateComponents([.hour, .minute], from: startTime)
            let end = calendar.dateComponents([.hour, .minute], from: endTime)
            guard let startHour = start.hour, let startMinute = start.minute,
                  let endHour = end.hour, let endMinute = end.minute,
                  startHour * 60 + startMinute != endHour * 60 + endMinute else {
                return nil
            }

            var startComps = DateComponents()
            startComps.hour = startHour
            startComps.minute = startMinute

            var endComps = DateComponents()
            endComps.hour = endHour
            endComps.minute = endMinute
            endComps.day = crossesMidnight ? 1 : nil

            return DeviceActivitySchedule(
                intervalStart: startComps,
                intervalEnd: endComps,
                repeats: true
            )
        }

        var crossesMidnight: Bool {
            let calendar = Calendar.current
            return minutes(from: startTime, calendar: calendar) > minutes(from: endTime, calendar: calendar)
        }

        private func minutes(from date: Date, calendar: Calendar) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
    }

    // MARK: - Weekday Enum

    /// Represents a day of the week for scheduling.
    enum Weekday: String, Codable, CaseIterable, Identifiable {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday

        var id: String { self.rawValue }

        var shortName: String {
            switch self {
            case .sunday: return "Dom"
            case .monday: return "Lun"
            case .tuesday: return "Mar"
            case .wednesday: return "Mié"
            case .thursday: return "Jue"
            case .friday: return "Vie"
            case .saturday: return "Sáb"
            }
        }

        /// Returns the Calendar.Component weekday value (1 for Sunday, 2 for Monday, etc.)
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
    }
}
