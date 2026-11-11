//
//  LimitsView.swift
//  FocusKey
//
//  Daily usage limits: once a profile's apps have been used for N minutes, they stay
//  blocked until midnight (or until the NFC tag is used).
//

import SwiftUI

struct LimitsView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var creating = false
    @State private var editing: UsageLimit?

    var body: some View {
        NavigationStack {
            List {
                if model.limits.isEmpty {
                    ContentUnavailableView(
                        "Sin límites",
                        systemImage: "hourglass",
                        description: Text("Crea un límite para bloquear un perfil cuando lo hayas usado cierto tiempo al día.")
                    )
                    .listRowBackground(Color.clear)
                }

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    ForEach(model.limits) { limit in
                        LimitRow(
                            limit: limit,
                            profile: model.profile(limit.profileID),
                            isBlocking: model.isLimitBlocking(limit, at: context.date),
                            isExtended: model.isLimitExtended(limit, at: context.date),
                            onToggle: { enabled in
                                var updated = limit
                                updated.isEnabled = enabled
                                model.updateLimit(updated)
                            },
                            onEdit: { editing = limit }
                        )
                        .swipeActions {
                            Button("Eliminar", role: .destructive) { model.deleteLimit(limit.id) }
                                .disabled(model.isLimitBlocking(limit, at: context.date))
                        }
                    }
                }

                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Añadir límite", systemImage: "plus")
                    }
                } footer: {
                    Text("El tiempo se cuenta desde medianoche. Al alcanzarlo, las apps quedan bloqueadas hasta el día siguiente. Con tu llave NFC puedes ampliar un límite alcanzado unos minutos más.")
                }
            }
            .navigationTitle("Límites")
            .sheet(isPresented: $creating) {
                LimitForm(limit: nil) { model.addLimit($0) }
            }
            .sheet(item: $editing) { limit in
                LimitForm(limit: limit) { model.updateLimit($0) }
            }
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let profile: FocusProfile?
    let isBlocking: Bool
    let isExtended: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
        HStack(spacing: 14) {
            ProfileIcon(symbol: profile?.symbol ?? "hourglass", color: profile?.color ?? .indigo)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(limit.displayName)
                        .foregroundStyle(.primary)
                    Text("\(UsageLimit.formatted(minutes: limit.minutes)) al día · \(profile?.displayName ?? String(localized: "Sin perfil"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isBlocking {
                        Label("Alcanzado hoy", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if isExtended {
                        Label("Ampliado con la llave", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isBlocking || isExtended)

            Spacer()

            Toggle("Activo", isOn: Binding(get: { limit.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(.green)
                .disabled(isBlocking || isExtended)
        }
        if isBlocking {
            ExtendLimitButton()
        }
        }
    }
}

private struct LimitForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: FocusModel
    let isNew: Bool
    let onSave: (UsageLimit) -> Void
    @State private var draft: UsageLimit

    init(limit: UsageLimit?, onSave: @escaping (UsageLimit) -> Void) {
        isNew = limit == nil
        self.onSave = onSave
        _draft = State(initialValue: limit ?? UsageLimit(profileID: nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Redes sociales, juegos…", text: $draft.name)
                }

                Section {
                    Picker("Perfil", selection: $draft.profileID) {
                        ForEach(model.profiles) { profile in
                            Label(profile.displayName, systemImage: profile.symbol).tag(Optional(profile.id))
                        }
                    }
                } header: {
                    Text("Qué limitar")
                } footer: {
                    Text("Se suma el tiempo de todas las apps, categorías y webs del perfil: \(model.profile(draft.profileID)?.summary ?? "").")
                }

                Section("Tiempo máximo al día") {
                    Stepper(value: $draft.minutes, in: 5...600, step: 5) {
                        Text(UsageLimit.formatted(minutes: draft.minutes))
                            .font(.title3.monospacedDigit())
                    }
                }

                Section {
                    Toggle("Límite activado", isOn: $draft.isEnabled)
                }
            }
            .navigationTitle(isNew ? String(localized: "Nuevo límite") : String(localized: "Editar límite"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if model.profiles.allSatisfy({ $0.id != draft.profileID }) {
                    draft.profileID = isNew ? model.activeProfileID : model.profile(draft.profileID)?.id
                }
            }
        }
    }
}

/// Asks how much extra time to grant on reached limits, then reads the NFC tag.
struct ExtendLimitButton: View {
    @EnvironmentObject private var model: FocusModel
    @EnvironmentObject private var nfc: NFCScanner
    @State private var choosing = false

    static let options = [5, 15, 30]

    var body: some View {
        Button {
            choosing = true
        } label: {
            Label("Ampliar con la llave", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(.orange)
        .confirmationDialog("¿Cuánto tiempo más?", isPresented: $choosing, titleVisibility: .visible) {
            ForEach(Self.options, id: \.self) { minutes in
                Button("+\(UsageLimit.formatted(minutes: minutes))") {
                    nfc.start { model.extendLimits(minutes: minutes) }
                }
            }
        } message: {
            Text("Acerca tu llave FocusKey para confirmar. Cuando gastes ese tiempo, se volverá a bloquear.")
        }
    }
}
