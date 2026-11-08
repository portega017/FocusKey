import Foundation
import DeviceActivity

/// Receives DeviceActivity callbacks for schedules, timed sessions and daily usage limits.
/// Shared logic lives in `Shared/` (FocusLock, FocusStore).
final class FocusKeyMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let now = Date()

        if let id = FocusActivity.scheduleID(from: activity) {
            let running = FocusLock.refreshScheduleShield(starting: id, now: now)
            if let schedule = running.first(where: { $0.id == id }) {
                FocusStore.openRecord(kind: .schedule, title: schedule.displayName, sourceID: id.uuidString, at: now)
            }
        } else if let id = FocusActivity.limitID(from: activity) {
            // New day: forget yesterday's "reached" and extra-time marks for this limit.
            var reached = FocusStore.limitsReached()
            if let date = reached[id.uuidString], !Calendar.current.isDate(date, inSameDayAs: now) {
                reached.removeValue(forKey: id.uuidString)
                FocusStore.setLimitsReached(reached)
            }
            var extensions = FocusStore.limitExtensions()
            if let date = extensions[id.uuidString], !Calendar.current.isDate(date, inSameDayAs: now) {
                extensions.removeValue(forKey: id.uuidString)
                FocusStore.setLimitExtensions(extensions)
            }
            FocusLock.refreshLimitShield(now: now)
        }
        // Sessions: the shield was already applied when the session started.
        FocusLock.reloadWidgets()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let now = Date()

        if let id = FocusActivity.scheduleID(from: activity) {
            FocusStore.setScheduleSkips(FocusStore.scheduleSkips().filter { $0.value > now })
            FocusLock.refreshScheduleShield(ending: id, now: now)
            FocusStore.closeRecords(sourceID: id.uuidString, at: now)
        } else if let id = FocusActivity.limitID(from: activity) {
            var reached = FocusStore.limitsReached()
            reached.removeValue(forKey: id.uuidString)
            FocusStore.setLimitsReached(reached)
            var extensions = FocusStore.limitExtensions()
            extensions.removeValue(forKey: id.uuidString)
            FocusStore.setLimitExtensions(extensions)
            FocusLock.refreshLimitShield(now: now)
            FocusStore.closeRecords(sourceID: id.uuidString, at: now)
        } else if activity == FocusActivity.session {
            // Only end the session this interval belongs to (not a newer one started since).
            if FocusStore.isManualLocked, let end = FocusStore.sessionEnd, end <= now.addingTimeInterval(60) {
                FocusLock.clearManualLock(at: now)
            }
        }
        FocusLock.reloadWidgets()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if event == UsageLimit.extraEventName, let id = FocusActivity.extraID(from: activity) {
            FocusLock.endLimitExtension(id)
            return
        }
        guard event == UsageLimit.eventName,
              let id = FocusActivity.limitID(from: activity),
              let limit = FocusStore.limits().first(where: { $0.id == id }),
              limit.isEnabled else { return }

        let now = Date()
        var reached = FocusStore.limitsReached()
        reached[id.uuidString] = now
        FocusStore.setLimitsReached(reached)
        FocusLock.refreshLimitShield(now: now)
        if FocusStore.isBlocking(limit, at: now) {
            FocusStore.openRecord(kind: .limit, title: limit.displayName, sourceID: id.uuidString, at: now)
        }
        FocusLock.reloadWidgets()
    }
}
