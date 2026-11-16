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
    @State private var deleting: UsageLimit?

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: Design.cardSpacing) {
                        if model.limits.isEmpty {
                            ContentUnavailableView {
                                Label("Sin límites", systemImage: "hourglass")
                            } description: {
                                Text("Crea un límite para bloquear un perfil cuando lo hayas usado cierto tiempo al día.")
                            } actions: {
                                Button("Añadir límite") { creating = true }
                                    .buttonStyle(.glassProminent)
                            }
                            .card()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(model.limits.enumerated()), id: \.element.id) { index, limit in
                                    if index > 0 {
                                        Divider().padding(.leading, 54)
                                    }
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
                                        onEdit: { editing = limit },
                                        onDelete: { deleting = limit }
                                    )
                                }
                            }
                            .card(padding: 14)
                        }

                        Text("El tiempo se cuenta desde medianoche. Al alcanzarlo, las apps quedan bloqueadas hasta el día siguiente. Con tu llave NFC puedes ampliar un límite alcanzado unos minutos más.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .screenBackground()
            .navigationTitle("Límites")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Añadir límite", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                LimitForm(limit: nil) { model.addLimit($0) }
            }
            .sheet(item: $editing) { limit in
                LimitForm(limit: limit) { model.updateLimit($0) }
            }
            .confirmationDialog(
                "¿Eliminar «\(deleting?.displayName ?? "")»?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    if let deleting { model.deleteLimit(deleting.id) }
                }
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
    let onDelete: () -> Void

    private var isLocked: Bool { isBlocking || isExtended }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        ProfileIcon(symbol: profile?.symbol ?? "hourglass", color: profile?.color ?? .accentColor, size: 42)
                            .opacity(limit.isEnabled ? 1 : 0.45)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(limit.displayName)
                                .font(.headline)
                                .foregroundStyle(limit.isEnabled ? .primary : .secondary)
                                .lineLimit(1)
                            Text(String(localized: "\(UsageLimit.formatted(minutes: limit.minutes)) al día"))
                                .font(.subheadline.weight(.medium))
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                            stateLine
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .opacity(isLocked ? 0 : 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .contextMenu {
                    Button("Editar", systemImage: "pencil", action: onEdit)
                    Button("Eliminar", systemImage: "trash", role: .destructive, action: onDelete)
                }

                Toggle("Activo", isOn: Binding(get: { limit.isEnabled }, set: onToggle))
                    .labelsHidden()
                    .disabled(isLocked)
                    .accessibilityLabel(limit.displayName)
            }

            if isBlocking {
                ExtendLimitButton()
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var stateLine: some View {
        if isBlocking {
            Label("Alcanzado hoy", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        } else if isExtended {
            Label("Ampliado con la llave", systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            Text(profile?.displayName ?? String(localized: "Sin perfil"))
                .font(.caption)
                .foregroundStyle(.secondary)
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
