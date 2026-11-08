import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var showingAddSchedule = false
    @State private var editingSchedule: FocusModel.Schedule?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.schedules.isEmpty {
                        ContentUnavailableView(
                            "Sin horarios",
                            systemImage: "calendar.badge.clock",
                            description: Text("Crea un horario para bloquear tus selecciones automáticamente.")
                        )
                        .padding(.vertical, 72)
                    }

                    // Re-evaluated every 30 s so cards lock/unlock when an interval starts or ends.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LazyVStack(spacing: 16) {
                            ForEach(model.schedules) { schedule in
                                ScheduleCard(
                                    schedule: schedule,
                                    profile: model.profile(schedule.profileID),
                                    isRunning: model.isScheduleActive(schedule, at: context.date),
                                    wouldStartNow: { model.isScheduleActive($0) },
                                    onUpdate: model.updateSchedule,
                                    onEdit: { editingSchedule = schedule },
                                    onDuplicate: { model.duplicateSchedule(schedule.id) },
                                    onDelete: { model.deleteSchedule(schedule.id) }
                                )
                            }
                        }
                    }

                    Button {
                        showingAddSchedule = true
                    } label: {
                        Label("Añadir horario", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Horarios")
        }
        .sheet(isPresented: $showingAddSchedule) {
            ScheduleForm(schedule: nil) { schedule in
                if let schedule { model.addSchedule(schedule) }
                showingAddSchedule = false
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            ScheduleForm(schedule: schedule) { updatedSchedule in
                if let updatedSchedule { model.updateSchedule(updatedSchedule) }
                editingSchedule = nil
            }
        }
    }
}

private struct ScheduleCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let schedule: FocusModel.Schedule
    let profile: FocusProfile?
    /// While running, the schedule can't be modified, disabled or deleted.
    let isRunning: Bool
    let wouldStartNow: (FocusModel.Schedule) -> Bool
    let onUpdate: (FocusModel.Schedule) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var showingStartNowAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.displayName)
                        .font(.title3.bold())
                    Label(profile?.displayName ?? String(localized: "Sin perfil"), systemImage: profile?.symbol ?? "lock.shield")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(badgeColor.opacity(0.14), in: Capsule())

                    Toggle(
                        schedule.isEnabled ? String(localized: "Activo") : String(localized: "Inactivo"),
                        isOn: Binding(get: { schedule.isEnabled }, set: { setEnabled($0) })
                    )
                    .labelsHidden()
                    .tint(.green)
                    .accessibilityLabel(schedule.isEnabled ? String(localized: "Horario activo") : String(localized: "Horario inactivo"))
                    .disabled(isRunning)
                }
            }

            if isRunning {
                Label(
                    "En curso — no se puede modificar hasta las \(schedule.endTime.formatted(date: .omitted, time: .shortened))",
                    systemImage: "lock.fill"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Días de la semana")
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(FocusModel.Weekday.mondayFirst) { weekday in
                        Text(weekday.initial)
                        .font(.headline)
                        .foregroundStyle(schedule.repeats.contains(weekday) ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(schedule.repeats.contains(weekday) ? Color.indigo : .clear, in: Circle())
                        .accessibilityLabel(weekday.shortName)
                        .accessibilityAddTraits(schedule.repeats.contains(weekday) ? .isSelected : [])
                    }
                }
            }

            timeControls

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Button("Editar", action: onEdit)
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                Button("Duplicar", action: onDuplicate)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Eliminar", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.secondary.opacity(0.2)) }
        .startsNowAlert(isPresented: $showingStartNowAlert, endTime: schedule.endTime) {
            var updated = schedule
            updated.isEnabled = true
            onUpdate(updated)
        }
    }

    @ViewBuilder
    private var timeControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                timeLabel(title: String(localized: "Hora de inicio"), time: schedule.startTime)
                timeLabel(title: String(localized: "Hora de fin"), time: schedule.endTime)
            }
        } else {
            HStack(spacing: 12) {
                timeLabel(title: String(localized: "Hora de inicio"), time: schedule.startTime)
                timeLabel(title: String(localized: "Hora de fin"), time: schedule.endTime)
            }
        }
    }

    private var badgeText: String {
        if isRunning { return String(localized: "En curso") }
        return schedule.isEnabled ? String(localized: "Activo") : String(localized: "Inactivo")
    }

    private var badgeColor: Color {
        if isRunning { return .orange }
        return schedule.isEnabled ? .green : .secondary
    }

    private var summary: String {
        let days = FocusModel.Weekday.mondayFirst
            .filter { schedule.repeats.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
        let recurrence = days.isEmpty ? String(localized: "Sin días seleccionados") : String(localized: "Se repite \(days)")
        let overnight = schedule.crossesMidnight ? String(localized: " (termina al día siguiente)") : ""
        return String(localized: "\(recurrence), de \(schedule.startTime.formatted(date: .omitted, time: .shortened)) a \(schedule.endTime.formatted(date: .omitted, time: .shortened))\(overnight).")
    }

    /// Read-only: times are changed only from the edit form, which has a Save button.
    private func timeLabel(title: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
            profileID: profileID
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
