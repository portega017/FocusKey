import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var showingAddSchedule = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // Re-evaluated every 30 s so rows follow intervals starting and ending.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: Design.cardSpacing) {
                        if model.schedules.isEmpty {
                            ContentUnavailableView {
                                Label("Sin horarios", systemImage: "calendar.badge.clock")
                            } description: {
                                Text("Crea un horario para bloquear un perfil automáticamente cada semana.")
                            } actions: {
                                Button("Añadir horario") { showingAddSchedule = true }
                                    .buttonStyle(.glassProminent)
                            }
                            .card()
                        } else {
                            WeekOverview(schedules: model.schedules, profile: model.profile, now: context.date)
                            scheduleList(now: context.date)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .screenBackground()
            .navigationTitle("Horarios")
            .navigationDestination(for: UUID.self) { id in
                ScheduleDetailView(scheduleID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Añadir horario", systemImage: "plus") { showingAddSchedule = true }
                }
            }
        }
        .sheet(isPresented: $showingAddSchedule) {
            ScheduleForm(schedule: nil) { schedule in
                if let schedule { model.addSchedule(schedule) }
                showingAddSchedule = false
            }
        }
    }

    private func scheduleList(now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.schedules.enumerated()), id: \.element.id) { index, schedule in
                if index > 0 {
                    Divider().padding(.leading, 54)
                }
                ScheduleRow(
                    schedule: schedule,
                    profile: model.profile(schedule.profileID),
                    isRunning: model.isScheduleActive(schedule, at: now),
                    now: now,
                    wouldStartNow: { model.isScheduleActive($0) },
                    onUpdate: model.updateSchedule
                )
            }
        }
        .card(padding: 14)
    }
}

// MARK: - Row

/// One schedule: profile icon, name, times and days, state, and the on/off switch.
private struct ScheduleRow: View {
    let schedule: FocusModel.Schedule
    let profile: FocusProfile?
    let isRunning: Bool
    let now: Date
    let wouldStartNow: (FocusModel.Schedule) -> Bool
    let onUpdate: (FocusModel.Schedule) -> Void
    @State private var showingStartNowAlert = false

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: schedule.id) {
                HStack(spacing: 12) {
                    ProfileIcon(symbol: profile?.symbol ?? "calendar", color: profile?.color ?? .accentColor, size: 42)
                        .opacity(schedule.isEnabled ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.displayName)
                            .font(.headline)
                            .foregroundStyle(schedule.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                        Text(schedule.timeRange)
                            .font(.subheadline.weight(.medium))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        stateLine
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                schedule.isEnabled ? String(localized: "Activo") : String(localized: "Inactivo"),
                isOn: Binding(get: { schedule.isEnabled }, set: setEnabled)
            )
            .labelsHidden()
            .disabled(isRunning)
            .accessibilityLabel(schedule.displayName)
        }
        .padding(.vertical, 8)
        .startsNowAlert(isPresented: $showingStartNowAlert, endTime: schedule.endTime) {
            var updated = schedule
            updated.isEnabled = true
            onUpdate(updated)
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        if isRunning {
            Label(String(localized: "En curso hasta las \(schedule.endTime.formatted(date: .omitted, time: .shortened))"), systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        } else if schedule.isEnabled, let next = schedule.prunedPauses().first(where: { schedule.intervalEnd(after: schedule.intervalStart(on: $0)) > now }) {
            Label(String(localized: "Pausado el \(next.formatted(.dateTime.weekday(.abbreviated).day()))"), systemImage: "pause.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            Text(schedule.daysSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        var updated = schedule
        updated.isEnabled = enabled
        // Turning on a schedule whose time range includes "now" blocks immediately: ask first.
        if enabled && wouldStartNow(updated) {
            showingStartNowAlert = true
        } else {
            onUpdate(updated)
        }
    }
}

// MARK: - Detail

/// Everything about one schedule, with its actions. Native list, like other secondary screens.
private struct ScheduleDetailView: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    let scheduleID: UUID

    @State private var editing = false
    @State private var pausing = false
    @State private var confirmingDelete = false
    @State private var showingStartNowAlert = false

    private var schedule: FocusModel.Schedule? { model.schedules.first { $0.id == scheduleID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let schedule {
                content(schedule, now: context.date)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.schedules) {
            if schedule == nil { dismiss() }
        }
    }

    private func content(_ schedule: FocusModel.Schedule, now: Date) -> some View {
        let profile = model.profile(schedule.profileID)
        let isRunning = model.isScheduleActive(schedule, at: now)
        let pauses = schedule.prunedPauses().filter { schedule.intervalEnd(after: schedule.intervalStart(on: $0)) > now }

        return List {
            Section {
                HStack(spacing: 14) {
                    ProfileIcon(symbol: profile?.symbol ?? "calendar", color: profile?.color ?? .accentColor, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.displayName)
                            .font(.title3.bold())
                        Text(profile?.displayName ?? String(localized: "Sin perfil"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isRunning {
                        StatusBadge(text: String(localized: "En curso"), color: .orange)
                    } else {
                        StatusBadge(
                            text: schedule.isEnabled ? String(localized: "Activo") : String(localized: "Inactivo"),
                            color: schedule.isEnabled ? .green : .secondary
                        )
                    }
                }
                .padding(.vertical, 4)

                Toggle("Horario activado", isOn: Binding(get: { schedule.isEnabled }, set: { setEnabled($0, schedule) }))
                    .disabled(isRunning)
            } footer: {
                if isRunning {
                    Text("Está en curso: no se puede modificar, desactivar ni eliminar hasta las \(schedule.endTime.formatted(date: .omitted, time: .shortened)). Tu llave lo desbloquea hasta entonces.")
                }
            }

            Section("Horario") {
                LabeledContent("Inicio", value: schedule.startTime.formatted(date: .omitted, time: .shortened))
                LabeledContent("Fin") {
                    Text(schedule.endTime.formatted(date: .omitted, time: .shortened)
                         + (schedule.crossesMidnight ? String(localized: " (día siguiente)") : ""))
                }
                LabeledContent("Días", value: schedule.daysSummary)
            }

            if schedule.isEnabled {
                Section {
                    ForEach(pauses, id: \.self) { day in
                        HStack {
                            Label(day.formatted(.dateTime.weekday(.wide).day().month()), systemImage: "pause.circle")
                            Spacer()
                            Button("Quitar pausa") { model.resumeSchedule(schedule.id, on: day) }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Pausar un día", systemImage: "pause.circle") { pausing = true }
                } header: {
                    Text("Pausas")
                } footer: {
                    Text("Un día pausado no se bloquea. El resto de la semana sigue igual.")
                }
            }

            Section {
                Button("Editar", systemImage: "pencil") { editing = true }
                    .disabled(isRunning)
                Button("Duplicar", systemImage: "plus.square.on.square") { model.duplicateSchedule(schedule.id) }
                Button("Eliminar horario", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .disabled(isRunning)
            }
        }
        .navigationTitle(schedule.displayName)
        .sheet(isPresented: $editing) {
            ScheduleForm(schedule: schedule) { updated in
                if let updated { model.updateSchedule(updated) }
                editing = false
            }
        }
        .sheet(isPresented: $pausing) {
            // In strict mode the model asks for the tag before pausing.
            PauseDaySheet(schedule: schedule, needsKey: model.strictMode) { day in
                model.pauseSchedule(schedule.id, on: day)
            }
        }
        .confirmationDialog("¿Eliminar «\(schedule.displayName)»?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { model.deleteSchedule(schedule.id) }
        }
        .startsNowAlert(isPresented: $showingStartNowAlert, endTime: schedule.endTime) {
            var updated = schedule
            updated.isEnabled = true
            model.updateSchedule(updated)
        }
    }

    private func setEnabled(_ enabled: Bool, _ schedule: FocusModel.Schedule) {
        var updated = schedule
        updated.isEnabled = enabled
        if enabled && model.isScheduleActive(updated) {
            showingStartNowAlert = true
        } else {
            model.updateSchedule(updated)
        }
    }
}

// MARK: - Pause a day

/// Picks one upcoming day to skip. In strict mode pausing needs the NFC tag.
private struct PauseDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let schedule: FocusModel.Schedule
    let needsKey: Bool
    let onPause: (Date) -> Void
    @State private var selected: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(schedule.upcomingDays(), id: \.self) { day in
                        let paused = schedule.isPaused(on: day)
                        Button {
                            selected = day
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                                        .foregroundStyle(paused ? .secondary : .primary)
                                    Text(String(localized: "Desde las \(schedule.intervalStart(on: day).formatted(date: .omitted, time: .shortened))"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if paused {
                                    Text("Ya pausado").font(.caption).foregroundStyle(.secondary)
                                } else if selected == day {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(paused)
                    }
                } footer: {
                    Text(needsKey
                         ? String(localized: "Ese día el horario no bloqueará nada. Con el modo estricto tendrás que acercar tu llave NFC; quitar la pausa no la necesita.")
                         : String(localized: "Ese día el horario no bloqueará nada. Puedes quitar la pausa cuando quieras."))
                }
            }
            .navigationTitle("Pausar un día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needsKey ? String(localized: "Pausar con llave") : String(localized: "Pausar")) {
                        guard let selected else { return }
                        dismiss()
                        onPause(selected)
                    }
                    .disabled(selected == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ScheduleForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: FocusModel
    @State private var showingStartNowAlert = false
    let schedule: FocusModel.Schedule?
    var onSave: (FocusModel.Schedule?) -> Void

    @State private var name: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var repeats: Set<FocusModel.Weekday>
    @State private var isEnabled: Bool
    @State private var profileID: UUID?

    private struct ScheduleTemplate: Identifiable {
        let id: String
        let name: String
        let startHour: Int
        let endHour: Int
        let repeats: Set<FocusModel.Weekday>
    }

    private static let templates: [ScheduleTemplate] = [
        .init(id: "study", name: String(localized: "Estudio"), startHour: 9, endHour: 14, repeats: [.monday, .tuesday, .wednesday, .thursday, .friday]),
        .init(id: "work", name: String(localized: "Trabajo"), startHour: 9, endHour: 17, repeats: [.monday, .tuesday, .wednesday, .thursday, .friday]),
        .init(id: "sleep", name: String(localized: "Dormir"), startHour: 23, endHour: 7, repeats: Set(FocusModel.Weekday.allCases))
    ]

    init(schedule: FocusModel.Schedule?, onSave: @escaping (FocusModel.Schedule?) -> Void) {
        self.schedule = schedule
        self.onSave = onSave
        let defaultStart = Calendar.current.date(from: DateComponents(hour: 9)) ?? .now
        let defaultEnd = Calendar.current.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart
        _name = State(initialValue: schedule?.name ?? "")
        _startTime = State(initialValue: schedule?.startTime ?? defaultStart)
        _endTime = State(initialValue: schedule?.endTime ?? defaultEnd)
        _repeats = State(initialValue: schedule?.repeats ?? [.monday, .tuesday, .wednesday, .thursday, .friday])
        _isEnabled = State(initialValue: schedule?.isEnabled ?? true)
        _profileID = State(initialValue: schedule?.profileID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plantillas") {
                    ForEach(Self.templates) { template in
                        Button {
                            apply(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.name)
                                Text("\(formattedHour(template.startHour))–\(formattedHour(template.endHour))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    TextField("Nombre del horario", text: $name)
                } header: {
                    Text("Nombre")
                } footer: {
                    Text("Opcional. Usa un nombre que te ayude a identificar este bloqueo.")
                }

                Section {
                    Picker("Perfil", selection: $profileID) {
                        ForEach(model.profiles) { profile in
                            Label(profile.displayName, systemImage: profile.symbol).tag(Optional(profile.id))
                        }
                    }
                } header: {
                    Text("Qué bloquear")
                } footer: {
                    Text(model.profile(profileID)?.summary ?? "")
                }

                Section {
                    DatePicker("Inicio", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Fin", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Horario")
                } footer: {
                    Text("El horario puede terminar al día siguiente.")
                }

                Section {
                    ForEach(FocusModel.Weekday.mondayFirst) { weekday in
                        Toggle(weekday.shortName, isOn: Binding(
                            get: { repeats.contains(weekday) },
                            set: { isSelected in
                                if isSelected {
                                    repeats.insert(weekday)
                                } else {
                                    repeats.remove(weekday)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Repetición")
                } footer: {
                    Text("Elige al menos un día para activar este horario.")
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background((model.profile(profileID)?.color ?? .indigo).gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? String(localized: "Horario de concentración") : name)
                                .font(.headline)
                            Text(recurrenceSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Vista previa")
                }

                Section {
                    Toggle("Horario activado", isOn: $isEnabled)
                } header: {
                    Text("Estado")
                } footer: {
                    Text(isEnabled ? String(localized: "El bloqueo se aplicará en el horario indicado.") : String(localized: "Puedes guardarlo ahora y activarlo más tarde."))
                }
            }
            .navigationTitle(schedule == nil ? String(localized: "Nuevo horario") : String(localized: "Editar horario"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                        onSave(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if model.isScheduleActive(draft) {
                            showingStartNowAlert = true
                        } else {
                            save()
                        }
                    }
                    .disabled(repeats.isEmpty || startTime == endTime)
                }
            }
            .startsNowAlert(isPresented: $showingStartNowAlert, endTime: endTime, onConfirm: save)
            .onAppear {
                if profileID == nil || model.profiles.allSatisfy({ $0.id != profileID }) {
                    profileID = schedule == nil ? model.activeProfileID : model.profile(profileID)?.id
                }
            }
        }
    }

    private var draft: FocusModel.Schedule {
        FocusModel.Schedule(
            id: schedule?.id ?? UUID(),
            name: name,
            startTime: startTime,
            endTime: endTime,
            repeats: repeats,
            isEnabled: isEnabled,
            profileID: profileID,
            pausedDays: schedule?.pausedDays ?? []
        )
    }

    private func save() {
        onSave(draft)
        dismiss()
    }

    private var recurrenceSummary: String {
        let days = FocusModel.Weekday.mondayFirst
            .filter { repeats.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
        let recurrence = days.isEmpty ? String(localized: "Sin días seleccionados") : String(localized: "Se repite \(days)")
        let overnight = startTime > endTime ? String(localized: " · Termina al día siguiente") : ""
        return String(localized: "\(recurrence), de \(startTime.formatted(date: .omitted, time: .shortened)) a \(endTime.formatted(date: .omitted, time: .shortened))\(overnight).")
    }

    private func apply(_ template: ScheduleTemplate) {
        let calendar = Calendar.current
        name = template.name
        startTime = calendar.date(from: DateComponents(hour: template.startHour)) ?? startTime
        endTime = calendar.date(from: DateComponents(hour: template.endHour)) ?? endTime
        repeats = template.repeats
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

// MARK: - Week overview

/// The whole week at a glance: one column per day, blocks colored by profile.
private struct WeekOverview: View {
    let schedules: [FocusModel.Schedule]
    let profile: (UUID?) -> FocusProfile?
    let now: Date

    private let height: CGFloat = 120
    private let dayMinutes = CGFloat(24 * 60)

    var body: some View {
        VStack(alignment: .leading, spacing: Design.contentSpacing) {
            CardHeader("Tu semana")

            HStack(alignment: .top, spacing: 6) {
                hourLabels
                ForEach(FocusModel.Weekday.mondayFirst) { day in
                    column(for: day)
                }
            }

            legend
        }
        .card()
    }

    private var hourLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(verbatim: "\(hour)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(height: height / 4, alignment: .top)
            }
        }
        .padding(.top, 22)
        .accessibilityHidden(true)
    }

    private func column(for day: FocusModel.Weekday) -> some View {
        let isToday = FocusModel.Weekday.of(now) == day
        let pieces = schedules.flatMap { schedule in
            schedule.weekSegments().filter { $0.weekday == day }.map { (schedule, $0) }
        }
        return VStack(spacing: 6) {
            Text(day.initial)
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
                .frame(height: 16)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, item in
                    let (schedule, piece) = item
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill((profile(schedule.profileID)?.color ?? .indigo).gradient)
                        .frame(height: max(3, CGFloat(piece.endMinute - piece.startMinute) / dayMinutes * height))
                        .padding(.horizontal, 2)
                        .offset(y: CGFloat(piece.startMinute) / dayMinutes * height)
                }
                if isToday {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(height: 2)
                        .offset(y: CGFloat(FocusModel.Schedule.minutes(now)) / dayMinutes * height - 1)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.shortName)
        .accessibilityValue(pieces.isEmpty
            ? String(localized: "Sin bloqueos")
            : pieces.map { "\($0.0.displayName) \(Self.hhmm($0.1.startMinute))–\(Self.hhmm($0.1.endMinute))" }.joined(separator: ", "))
    }

    /// One entry per profile in use, so colors never carry meaning on their own.
    @ViewBuilder
    private var legend: some View {
        let ids = schedules.filter(\.isEnabled).map { profile($0.profileID)?.id }
        let used = ids.reduce(into: [UUID]()) { result, id in
            if let id, !result.contains(id) { result.append(id) }
        }.compactMap { profile($0) }
        if !used.isEmpty {
            HStack(spacing: 14) {
                ForEach(used) { item in
                    HStack(spacing: 5) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func hhmm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }
}

private extension FocusModel.Weekday {
    static let mondayFirst: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var initial: String {
        switch self {
        case .monday: return String(localized: "L")
        case .tuesday: return String(localized: "M")
        case .wednesday: return String(localized: "X")
        case .thursday: return String(localized: "J")
        case .friday: return String(localized: "V")
        case .saturday: return String(localized: "S")
        case .sunday: return String(localized: "D")
        }
    }
}

private extension View {
    /// Warns that saving/enabling will block apps right away and lock the schedule until it ends.
    func startsNowAlert(isPresented: Binding<Bool>, endTime: Date, onConfirm: @escaping () -> Void) -> some View {
        alert("El bloqueo empezará ahora", isPresented: isPresented) {
            Button("Cancelar", role: .cancel) {}
            Button("Bloquear ahora", role: .destructive, action: onConfirm)
        } message: {
            Text("Este horario incluye la hora actual. Las apps se bloquearán ya y no podrás modificar ni desactivar el horario hasta las \(endTime.formatted(date: .omitted, time: .shortened)).")
        }
    }
}

extension FocusModel.Schedule {
    /// "7:00 – 15:00"
    var timeRange: String {
        "\(startTime.formatted(date: .omitted, time: .shortened)) – \(endTime.formatted(date: .omitted, time: .shortened))"
    }

    /// "Lunes a viernes", "Todos los días", "Fines de semana" or "Lun, Mié, Vie".
    var daysSummary: String {
        let workdays: Set<FocusModel.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekend: Set<FocusModel.Weekday> = [.saturday, .sunday]
        switch repeats {
        case Set(FocusModel.Weekday.allCases): return String(localized: "Todos los días")
        case workdays: return String(localized: "Lunes a viernes")
        case weekend: return String(localized: "Fines de semana")
        case []: return String(localized: "Sin días seleccionados")
        default:
            return FocusModel.Weekday.mondayFirst.filter { repeats.contains($0) }.map(\.shortName).joined(separator: ", ")
        }
    }
}
