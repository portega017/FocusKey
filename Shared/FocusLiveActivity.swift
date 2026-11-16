//
//  FocusLiveActivity.swift
//  FocusKey
//
//  Live Activity (Lock Screen and Dynamic Island) with the countdown of a timed session or of
//  the current pomodoro phase. The attributes are shared with the widget extension, which
//  draws it; only the app process starts, updates and ends it (`sync`).
//
//  The monitor extension can't update Live Activities, so a pomodoro phase change is shown
//  when the app next runs. Until then the activity goes stale at the end of the phase and says so.
//

import ActivityKit
import Foundation

nonisolated struct FocusActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var isBreak: Bool
        var start: Date
        var end: Date
    }

    var profileName: String
    var symbol: String
    var colorName: String
}

@MainActor
enum FocusLiveActivity {
    /// Starts, updates or ends the Live Activity so it matches what is running now.
    static func sync(now: Date = .now) async {
        let current = Activity<FocusActivityAttributes>.activities
        // Turned off in Settings: behave as if nothing were running.
        guard FocusStore.liveActivities, let (attributes, state) = desired(at: now) else {
            for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: state.end)

        if let existing = current.first(where: { $0.attributes == attributes && $0.activityState == .active }) {
            if existing.content.state != state { await existing.update(content) }
            for other in current where other.id != existing.id { await other.end(nil, dismissalPolicy: .immediate) }
            return
        }
        for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    static func desired(at now: Date) -> (FocusActivityAttributes, FocusActivityAttributes.ContentState)? {
        let status = FocusStatus.current(at: now)

        if let plan = status.pomodoro, let phase = status.pomodoroPhase,
           let profile = FocusStore.profile(plan.profileID) {
            let attributes = FocusActivityAttributes(profileName: profile.displayName, symbol: profile.symbol, colorName: profile.colorName)
            let cycle = status.pomodoroCycleText ?? ""
            switch phase {
            case let .focus(_, start, end):
                return (attributes, .init(title: String(localized: "Concentración"), subtitle: cycle, isBreak: false, start: start, end: end))
            case let .rest(_, start, end):
                return (attributes, .init(title: String(localized: "Descanso"), subtitle: String(localized: "Después: \(cycle)"), isBreak: true, start: start, end: end))
            case .finished:
                return nil
            }
        }

        if status.isManualLocked, let start = status.sessionStart, let end = status.sessionEnd, end > now {
            let profile = status.manualProfile
            let attributes = FocusActivityAttributes(
                profileName: profile?.displayName ?? String(localized: "Perfil"),
                symbol: profile?.symbol ?? "lock.shield",
                colorName: profile?.colorName ?? "indigo"
            )
            return (attributes, .init(title: String(localized: "Sesión de concentración"), subtitle: attributes.profileName, isBreak: false, start: start, end: end))
        }
        return nil
    }
}
