//
//  PresetsView.swift
//  FocusKey
//
//  Session presets: one-tap timed sessions ("Redes · 1 h") shown on the main screen,
//  in Siri / Shortcuts and as a configurable Control Center button.
//

import SwiftUI

/// Grid of preset buttons for the main screen.
struct PresetGrid: View {
    @EnvironmentObject private var model: FocusModel
    let isDisabled: Bool
    @State private var editing: SessionPreset?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.contentSpacing) {
            CardHeader(
                "Sesiones rápidas",
                subtitle: model.presets.isEmpty ? String(localized: "Bloquea un perfil durante un tiempo con un toque.") : nil
            ) {
                if !model.presets.isEmpty {
                    NavigationLink("Gestionar") { PresetsView() }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.presets) { preset in
                    PresetTile(preset: preset, profile: model.profile(preset.profileID)) {
                        model.startPreset(preset)
                    }
                    .contextMenu {
                        Button("Editar", systemImage: "pencil") { editing = preset }
                        Button("Eliminar", systemImage: "trash", role: .destructive) { model.deletePreset(preset.id) }
                    }
                }

                Button {
                    creating = true
                } label: {
                    Label("Nueva", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: PresetTile.height)
                        .background {
                            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.tint.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .card()
        .sheet(item: $editing) { preset in
            PresetEditor(preset: preset) { model.updatePreset($0) }
        }
        .sheet(isPresented: $creating) {
            PresetEditor(preset: nil) { model.addPreset($0) }
        }
    }
}

private struct PresetTile: View {
    let preset: SessionPreset
    let profile: FocusProfile?
    let action: () -> Void

    static let height: CGFloat = 68

    private var color: Color { profile?.color ?? .accentColor }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: profile?.symbol ?? "timer")
                        .font(.headline)
                    Spacer()
                    Text(UsageLimit.formatted(minutes: preset.minutes))
                        .font(.caption.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(preset.displayName(profile: profile))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Empezar \(preset.title(profile: profile))"))
    }
}

/// List to reorder, edit and delete presets.
struct PresetsView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var editing: SessionPreset?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(model.presets) { preset in
                    let profile = model.profile(preset.profileID)
                    Button {
                        editing = preset
                    } label: {
                        HStack(spacing: 14) {
                            ProfileIcon(symbol: profile?.symbol ?? "timer", color: profile?.color ?? .indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName(profile: profile)).foregroundStyle(.primary)
                                Text("\(profile?.displayName ?? "") · \(UsageLimit.formatted(minutes: preset.minutes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { model.deletePreset(model.presets[index].id) }
                }
                .onMove(perform: model.movePresets)
            } footer: {
                Text("También puedes empezarlas con Siri («Empezar … con FocusKey») o añadir un botón en el Centro de Control.")
            }

            Section {
                Button {
                    creating = true
                } label: {
                    Label("Nueva sesión rápida", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Sesiones rápidas")
        .toolbar { EditButton() }
        .sheet(item: $editing) { preset in
            PresetEditor(preset: preset) { model.updatePreset($0) }
        }
        .sheet(isPresented: $creating) {
            PresetEditor(preset: nil) { model.addPreset($0) }
        }
    }
}

struct PresetEditor: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    let preset: SessionPreset?
    let onSave: (SessionPreset) -> Void

    @State private var name: String
    @State private var profileID: UUID?
    @State private var minutes: Int

    init(preset: SessionPreset?, onSave: @escaping (SessionPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
        _profileID = State(initialValue: preset?.profileID)
        _minutes = State(initialValue: preset?.minutes ?? 60)
    }

    private var profile: FocusProfile? { model.profile(profileID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Perfil", selection: $profileID) {
                        ForEach(model.profiles) { profile in
                            Label(profile.displayName, systemImage: profile.symbol).tag(Optional(profile.id))
                        }
                    }
                } header: {
                    Text("Qué bloquear")
                } footer: {
                    Text(profile?.summary ?? "")
                }

                Section("Duración") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SessionPreset.durationOptions, id: \.self) { option in
                                Button(UsageLimit.formatted(minutes: option)) { minutes = option }
                                    .buttonStyle(.bordered)
                                    .tint(option == minutes ? (profile?.color ?? .indigo) : .secondary)
                            }
                        }
                    }
                    Stepper(value: $minutes, in: FocusLock.minimumSessionMinutes...720, step: 15) {
                        Text(UsageLimit.formatted(minutes: minutes))
                            .font(.title3.monospacedDigit())
                    }
                }

                Section {
                    TextField(profile?.displayName ?? String(localized: "Nombre"), text: $name)
                } header: {
                    Text("Nombre")
                } footer: {
                    Text("Opcional. Si lo dejas vacío se usa el nombre del perfil.")
                }

                Section("Vista previa") {
                    PresetTile(preset: draft, profile: profile) {}
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            .navigationTitle(preset == nil ? String(localized: "Nueva sesión rápida") : String(localized: "Editar sesión rápida"))
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
                    .disabled(profileID == nil)
                }
            }
            .onAppear {
                if profileID == nil || model.profiles.allSatisfy({ $0.id != profileID }) {
                    profileID = model.activeProfileID ?? model.profiles.first?.id
                }
            }
        }
    }

    private var draft: SessionPreset {
        SessionPreset(
            id: preset?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            profileID: profileID ?? UUID(),
            minutes: minutes
        )
    }
}
