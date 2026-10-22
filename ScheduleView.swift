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
    let schedule: FocusModel.Schedule
    let onUpdate: (FocusModel.Schedule) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name.isEmpty ? "Horario de concentración" : schedule.name)
                        .font(.title3.bold())
                    Text("Bloqueo programado")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    schedule.isEnabled ? "Activo" : "Inactivo",
                    isOn: Binding(get: { schedule.isEnabled }, set: { update(isEnabled: $0) })
                )
                .labelsHidden()
                .tint(.green)
                .accessibilityLabel(schedule.isEnabled ? "Horario activo" : "Horario inactivo")
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Días de la semana")
                    .font(.headline)
                HStack {
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
                        .frame(width: 42, height: 42)
                        .background(schedule.repeats.contains(weekday) ? Color.blue : .clear, in: Circle())
                        .accessibilityLabel(weekday.shortName)
                        .accessibilityAddTraits(schedule.repeats.contains(weekday) ? .isSelected : [])
                    }
                }
            }

            HStack(spacing: 16) {
                timePicker(title: "Hora de inicio", time: schedule.startTime) { update(startTime: $0) }
                timePicker(title: "Hora de fin", time: schedule.endTime) { update(endTime: $0) }
            }

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Editar", action: onEdit)
                Spacer()
                Button("Eliminar", role: .destructive, action: onDelete)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(Color.secondary.opacity(0.25)) }
    }

    private var summary: String {
        let days = FocusModel.Weekday.mondayFirst
            .filter { schedule.repeats.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
        return "\(days.isEmpty ? "Sin días seleccionados" : days): \(schedule.startTime.formatted(date: .omitted, time: .shortened))–\(schedule.endTime.formatted(date: .omitted, time: .shortened))."
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
                Section("Información básica") {
                    TextField("Nombre", text: $name)
                    DatePicker("Hora de inicio", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hora de fin", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section("Días de la semana") {
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
                }
                Section { Toggle("Activado", isOn: $isEnabled) }
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
