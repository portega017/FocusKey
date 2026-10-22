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

                    ForEach(model.schedules) { schedule in
                        ScheduleCard(
                            schedule: schedule,
                            onUpdate: model.updateSchedule,
                            onEdit: { editingSchedule = schedule },
                            onDelete: { model.deleteSchedule(schedule.id) }
                        )
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
    let onUpdate: (FocusModel.Schedule) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name.isEmpty ? "Horario de concentración" : schedule.name)
                        .font(.title3.bold())
                    Text("Bloqueo programado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(schedule.isEnabled ? "Activo" : "Inactivo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(schedule.isEnabled ? .green : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            (schedule.isEnabled ? Color.green : Color.secondary).opacity(0.14),
                            in: Capsule()
                        )

                    Toggle(
                        schedule.isEnabled ? "Activo" : "Inactivo",
                        isOn: Binding(get: { schedule.isEnabled }, set: { update(isEnabled: $0) })
                    )
                    .labelsHidden()
                    .tint(.green)
                    .accessibilityLabel(schedule.isEnabled ? "Horario activo" : "Horario inactivo")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Días de la semana")
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(FocusModel.Weekday.mondayFirst) { weekday in
                        Button(weekday.initial) {
                            var repeats = schedule.repeats
                            if repeats.contains(weekday) {
                                repeats.remove(weekday)
                            } else {
                                repeats.insert(weekday)
                            }
                            update(repeats: repeats)
                        }
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
                Spacer()
                Button("Eliminar", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.secondary.opacity(0.2)) }
    }

    @ViewBuilder
    private var timeControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                timePicker(title: "Hora de inicio", time: schedule.startTime) { update(startTime: $0) }
                timePicker(title: "Hora de fin", time: schedule.endTime) { update(endTime: $0) }
            }
        } else {
            HStack(spacing: 12) {
                timePicker(title: "Hora de inicio", time: schedule.startTime) { update(startTime: $0) }
                timePicker(title: "Hora de fin", time: schedule.endTime) { update(endTime: $0) }
            }
        }
    }

    private var summary: String {
        let days = FocusModel.Weekday.mondayFirst
            .filter { schedule.repeats.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
        let recurrence = days.isEmpty ? "Sin días seleccionados" : "Se repite \(days)"
        return "\(recurrence), de \(schedule.startTime.formatted(date: .omitted, time: .shortened)) a \(schedule.endTime.formatted(date: .omitted, time: .shortened))."
    }

    private func timePicker(title: String, time: Date, onChange: @escaping (Date) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            DatePicker(title, selection: Binding(get: { time }, set: onChange), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func update(
        startTime: Date? = nil,
        endTime: Date? = nil,
        repeats: Set<FocusModel.Weekday>? = nil,
        isEnabled: Bool? = nil
    ) {
        var updated = schedule
        if let startTime { updated.startTime = startTime }
        if let endTime { updated.endTime = endTime }
        if let repeats { updated.repeats = repeats }
        if let isEnabled { updated.isEnabled = isEnabled }
        onUpdate(updated)
    }
}

struct ScheduleForm: View {
    @Environment(\.dismiss) private var dismiss
    let schedule: FocusModel.Schedule?
    var onSave: (FocusModel.Schedule?) -> Void

    @State private var name: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var repeats: Set<FocusModel.Weekday>
    @State private var isEnabled: Bool

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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del horario", text: $name)
                } header: {
                    Text("Nombre")
                } footer: {
                    Text("Opcional. Usa un nombre que te ayude a identificar este bloqueo.")
                }

                Section {
                    DatePicker("Inicio", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Fin", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Horario")
                } footer: {
                    Text("La hora de fin debe ser posterior a la hora de inicio.")
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
                            Text(name.isEmpty ? "Horario de concentración" : name)
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
                    Text(isEnabled ? "El bloqueo se aplicará en el horario indicado." : "Puedes guardarlo ahora y activarlo más tarde.")
                }
            }
            .navigationTitle(schedule == nil ? "Nuevo horario" : "Editar horario")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                        onSave(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(FocusModel.Schedule(
                            id: schedule?.id ?? UUID(),
                            name: name,
                            startTime: startTime,
                            endTime: endTime,
                            repeats: repeats,
                            isEnabled: isEnabled
                        ))
                        dismiss()
                    }
                    .disabled(repeats.isEmpty || startTime >= endTime)
                }
            }
        }
    }

    private var recurrenceSummary: String {
        let days = FocusModel.Weekday.mondayFirst
            .filter { repeats.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
        let recurrence = days.isEmpty ? "Sin días seleccionados" : "Se repite \(days)"
        return "\(recurrence), de \(startTime.formatted(date: .omitted, time: .shortened)) a \(endTime.formatted(date: .omitted, time: .shortened))."
    }
}

private extension FocusModel.Weekday {
    static let mondayFirst: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var initial: String {
        switch self {
        case .monday: return "L"
        case .tuesday: return "M"
        case .wednesday: return "X"
        case .thursday: return "J"
        case .friday: return "V"
        case .saturday: return "S"
        case .sunday: return "D"
        }
    }
}
