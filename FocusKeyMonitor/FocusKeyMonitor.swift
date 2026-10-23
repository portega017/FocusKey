import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

final class FocusKeyMonitor: DeviceActivityMonitor {
    private static let appGroupID = "group.com.example.FocusKey"
    private static let sharedDefaults = UserDefaults(suiteName: appGroupID)!
    private static let lockStateKey = "FocusKey.isLocked"
    private static let selectionKey = "FocusKeySelection"
    private static let schedulesKey = "FocusKeySchedules"
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard isScheduledForToday(activity) else { return }
        applyScheduledLock()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard !hasActiveScheduleNow() else { return }
        clearScheduledLock()
    }

    private func applyScheduledLock() {
        guard let selection = loadSelection(), hasSelection(selection) else {
            clearScheduledLock()
            return
        }

        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens
        Self.sharedDefaults.set(true, forKey: Self.lockStateKey)
    }

    private func clearScheduledLock() {
        store.clearAllSettings()
        Self.sharedDefaults.set(false, forKey: Self.lockStateKey)
    }

    private func loadSelection() -> FamilyControls.FamilyActivitySelection? {
        guard let data = Self.sharedDefaults.data(forKey: Self.selectionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: data)
    }

    private func hasSelection(_ selection: FamilyControls.FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    private func isScheduledForToday(_ activity: DeviceActivityName) -> Bool {
        let prefix = "FocusKeySchedule_"
        guard activity.rawValue.hasPrefix(prefix),
              let id = UUID(uuidString: String(activity.rawValue.dropFirst(prefix.count))),
              let schedule = loadSchedules().first(where: { $0.id == id }) else {
            return false
        }

        return schedule.isEnabled && schedule.repeats.contains(currentWeekday)
    }

    private func hasActiveScheduleNow() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentMinutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)

        return loadSchedules().contains { schedule in
            guard schedule.isEnabled else {
                return false
            }
            let startMinutes = minutes(for: schedule.startTime, calendar: calendar)
            let endMinutes = minutes(for: schedule.endTime, calendar: calendar)

            if startMinutes < endMinutes {
                return schedule.repeats.contains(currentWeekday)
                    && currentMinutes >= startMinutes
                    && currentMinutes < endMinutes
            }

            if currentMinutes >= startMinutes {
                return schedule.repeats.contains(currentWeekday)
            }

            return currentMinutes < endMinutes
                && schedule.repeats.contains(previousWeekday)
        }
    }

    private var currentWeekday: String {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1: return "sunday"
        case 2: return "monday"
        case 3: return "tuesday"
        case 4: return "wednesday"
        case 5: return "thursday"
        case 6: return "friday"
        default: return "saturday"
        }
    }

    private var previousWeekday: String {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1: return "saturday"
        case 2: return "sunday"
        case 3: return "monday"
        case 4: return "tuesday"
        case 5: return "wednesday"
        case 6: return "thursday"
        default: return "friday"
        }
    }

    private func minutes(for date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private func loadSchedules() -> [StoredSchedule] {
        guard let data = Self.sharedDefaults.data(forKey: Self.schedulesKey),
              let schedules = try? JSONDecoder().decode([StoredSchedule].self, from: data) else {
            return []
        }
        return schedules
    }

    private struct StoredSchedule: Decodable {
        let id: UUID
        let startTime: Date
        let endTime: Date
        let repeats: Set<String>
        let isEnabled: Bool

        private enum CodingKeys: String, CodingKey {
            case id, startTime, endTime, time, repeats, isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
                ?? container.decode(Date.self, forKey: .time)
            endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
                ?? Calendar.current.date(byAdding: .minute, value: 15, to: startTime)!
            repeats = try container.decode(Set<String>.self, forKey: .repeats)
            isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        }
    }
}
