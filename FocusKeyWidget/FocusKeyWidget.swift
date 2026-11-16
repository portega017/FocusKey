import WidgetKit
import SwiftUI
import AppIntents

@main
struct FocusKeyWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusStatusWidget()
        FocusLockControl()
        FocusUnlockControl()
        FocusPresetControl()
        FocusLiveActivityWidget()
    }
}

// MARK: - Timeline

struct FocusEntry: TimelineEntry {
    let date: Date
    let isBlocked: Bool
    let canUnlockWithKey: Bool
    let headline: String
    let detail: String?
    let sessionEnd: Date?
    let sessionStart: Date?
    let profileName: String
    let profileSymbol: String
    let colorName: String
    /// First quick sessions, offered as buttons by the medium widget.
    var presets: [PresetItem] = []

    struct PresetItem: Identifiable {
        let entity: SessionPresetEntity
        let name: String
        let duration: String
        let symbol: String
        let colorName: String
        var id: UUID { entity.id }
    }

    var color: Color { FocusPalette.color(colorName) }

    /// Running session interval, for progress rings that update on their own.
    var sessionInterval: ClosedRange<Date>? {
        guard let start = sessionStart, let end = sessionEnd, end > start else { return nil }
        return start...end
    }

    static func make(at date: Date) -> FocusEntry {
        let status = FocusStatus.current(at: date)
        let profiles = FocusStore.profiles()
        let profile = status.blockingProfile ?? FocusStore.profile(FocusStore.activeProfileID, in: profiles)
        let presets = FocusStore.presets().prefix(2).map { preset in
            let presetProfile = profiles.first { $0.id == preset.profileID }
            return PresetItem(
                entity: SessionPresetEntity(preset, profiles: profiles),
                name: preset.displayName(profile: presetProfile),
                duration: preset.durationText,
                symbol: presetProfile?.symbol ?? "timer",
                colorName: presetProfile?.colorName ?? "indigo"
            )
        }
        return FocusEntry(
            date: date,
            isBlocked: status.isBlocked,
            canUnlockWithKey: status.canUnlockWithKey,
            headline: status.headline,
            detail: status.detail,
            sessionEnd: status.sessionEnd,
            sessionStart: status.sessionStart,
            profileName: profile?.displayName ?? String(localized: "Sin perfil"),
            profileSymbol: profile?.symbol ?? "lock.shield",
            colorName: profile?.colorName ?? "indigo",
            presets: Array(presets)
        )
    }
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, isBlocked: false, canUnlockWithKey: false, headline: String(localized: "Desbloqueado"), detail: nil, sessionEnd: nil, sessionStart: nil, profileName: String(localized: "General"), profileSymbol: "lock.shield", colorName: "indigo")
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(.make(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date.now
        var dates = [now]
        // An entry when the current block ends, plus the start/end of upcoming schedules today.
        if let change = FocusStatus.current(at: now).nextChange { dates.append(change.addingTimeInterval(1)) }
        let calendar = Calendar.current
        for schedule in FocusStore.schedules() where schedule.isEnabled {
            for time in [schedule.startTime, schedule.endTime] {
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                if let next = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime),
                   next.timeIntervalSince(now) < 24 * 60 * 60 {
                    dates.append(next.addingTimeInterval(1))
                }
            }
        }
        let entries = Set(dates).sorted().map(FocusEntry.make(at:))
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }
}

// MARK: - Status widget

struct FocusStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusKeyStatus", provider: FocusProvider()) { entry in
            FocusStatusView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [entry.color.opacity(entry.isBlocked ? 0.35 : 0.18), entry.color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Estado de FocusKey")
        .description("Mira si tus apps están bloqueadas y bloquéalas con un toque.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct FocusStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    private var tint: Color { entry.isBlocked ? entry.color : .green }
    private var lockSymbol: String { entry.isBlocked ? "lock.fill" : "lock.open.fill" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.headline, systemImage: lockSymbol)
        case .accessoryCircular:
            if let interval = entry.sessionInterval {
                ProgressView(timerInterval: interval, countsDown: true) {
                    Image(systemName: lockSymbol)
                } currentValueLabel: {
                    Image(systemName: lockSymbol)
                }
                .progressViewStyle(.circular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: lockSymbol).font(.title2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(entry.headline, systemImage: lockSymbol).font(.headline)
                if let end = entry.sessionEnd {
                    Text(end, style: .timer).fontDesign(.rounded).monospacedDigit()
                } else if let detail = entry.detail {
                    Text(detail).lineLimit(2)
                } else {
                    Text(entry.profileName)
                }
            }
        default:
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: entry.profileSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(entry.color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                if let interval = entry.sessionInterval {
                    ProgressView(timerInterval: interval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .tint(tint)
                    .frame(width: 28, height: 28)
                } else {
                    Image(systemName: lockSymbol)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.headline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let end = entry.sessionEnd {
                    Text(end, style: .timer)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                } else {
                    Text(entry.detail ?? entry.profileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? 2 : 1)
                }
            }

            Spacer(minLength: 0)

            actions
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var actions: some View {
        if entry.canUnlockWithKey {
            Button(intent: UnlockWithKeyIntent()) {
                Label("Usar llave", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
            }
            .tint(entry.color)
        } else if family == .systemMedium, !entry.isBlocked, !entry.presets.isEmpty {
            // Quick sessions, like on the main screen.
            HStack(spacing: 8) {
                ForEach(entry.presets) { preset in
                    Button(intent: StartPresetIntent(preset: preset.entity)) {
                        HStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                            Text(preset.name).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(preset.duration)
                                .font(.caption.weight(.bold))
                                .fontDesign(.rounded)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(FocusPalette.color(preset.colorName))
                }
            }
        } else if family == .systemMedium {
            HStack {
                Button(intent: LockFocusIntent()) {
                    Label("Bloquear", systemImage: "lock.fill").frame(maxWidth: .infinity)
                }
                Button(intent: LockFocusIntent(minutes: 60)) {
                    Label("1 hora", systemImage: "timer").frame(maxWidth: .infinity)
                }
            }
            .tint(entry.color)
        } else {
            Button(intent: LockFocusIntent()) {
                Label("Bloquear", systemImage: "lock.fill").frame(maxWidth: .infinity)
            }
            .tint(entry.color)
        }
    }
}

// MARK: - Control Center

struct FocusLockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FocusKeyLockControl") {
            ControlWidgetButton(action: LockFocusIntent()) {
                Label("Bloquear apps", systemImage: "lock.fill")
            }
        }
        .displayName("Bloquear apps")
        .description("Bloquea el perfil seleccionado en FocusKey.")
    }
}

/// Starts a session preset chosen when the control is added.
struct FocusPresetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "FocusKeyPresetControl", intent: PresetControlConfiguration.self) { configuration in
            ControlWidgetButton(action: StartPresetIntent(preset: configuration.preset)) {
                Label(
                    configuration.preset?.title ?? String(localized: "Sesión rápida"),
                    systemImage: configuration.preset?.symbol ?? "bolt.fill"
                )
            }
        }
        .displayName("Sesión rápida")
        .description("Empieza una de tus sesiones rápidas de FocusKey.")
        .promptsForUserConfiguration()
    }
}

struct FocusUnlockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FocusKeyUnlockControl") {
            ControlWidgetButton(action: UnlockWithKeyIntent()) {
                Label("Usar llave", systemImage: "wave.3.right")
            }
        }
        .displayName("Desbloquear con llave")
        .description("Abre FocusKey para leer tu llave NFC.")
    }
}
