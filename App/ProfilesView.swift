//
//  ProfilesView.swift
//  FocusKey
//

import SwiftUI
import FamilyControls

struct ProfilesView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var editing: FocusProfile?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(model.profiles) { profile in
                    Button {
                        editing = profile
                    } label: {
                        HStack(spacing: 14) {
                            ProfileIcon(symbol: profile.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).foregroundStyle(.primary)
                                Text(profile.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.id == model.activeProfileID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions {
                        if model.profiles.count > 1 {
                            Button("Eliminar", role: .destructive) { model.deleteProfile(profile.id) }
                        }
                    }
                }
            } footer: {
                Text("Cada perfil es un grupo de apps, categorías y webs. Úsalos en el bloqueo manual, los horarios y los límites.")
            }

            Section {
                Button {
                    creating = true
                } label: {
                    Label("Nuevo perfil", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Perfiles")
        .sheet(item: $editing) { profile in
            ProfileEditor(profile: profile, lockReason: model.profileLockReason(profile.id)) { updated in
                model.updateProfile(updated)
            }
        }
        .sheet(isPresented: $creating) {
            ProfileEditor(profile: nil, lockReason: nil) { created in
                model.addProfile(created)
            }
        }
    }
}

struct ProfileIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    /// When set, the profile is blocking now and its apps can't change.
    let lockReason: String?
    let onSave: (FocusProfile) -> Void

    @State private var draft: FocusProfile
    @State private var showingPicker = false

    init(profile: FocusProfile?, lockReason: String?, onSave: @escaping (FocusProfile) -> Void) {
        isNew = profile == nil
        self.lockReason = lockReason
        self.onSave = onSave
        _draft = State(initialValue: profile ?? FocusProfile(name: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Trabajo, Estudio, Noche…", text: $draft.name)
                }

                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(FocusProfile.symbols, id: \.self) { symbol in
                            Button {
                                draft.symbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(draft.symbol == symbol ? .white : .primary)
                                    .background(
                                        draft.symbol == symbol ? Color.indigo : Color(uiColor: .tertiarySystemFill),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(draft.symbol == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Elegir apps y webs", systemImage: "apps.iphone")
                    }
                    .disabled(lockReason != nil)

                    ForEach(Array(draft.selection.applicationTokens), id: \.self) { token in
                        Label(token)
                    }
                    ForEach(Array(draft.selection.categoryTokens), id: \.self) { token in
                        Label(token)
                    }
                    ForEach(Array(draft.selection.webDomainTokens), id: \.self) { token in
                        Label(token)
                    }
                } header: {
                    Text("Bloquear")
                } footer: {
                    Text(lockReason ?? draft.summary)
                }
            }
            .navigationTitle(isNew ? "Nuevo perfil" : "Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingPicker, selection: $draft.selection)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
