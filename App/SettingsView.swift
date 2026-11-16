//
//  SettingsView.swift
//  FocusKey
//

import ActivityKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false
    @State private var showingOnboarding = false
    @State private var copied = false
    @State private var addingCard = false
    @State private var editingCard: CardKey?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Modo estricto", isOn: Binding(get: { model.strictMode }, set: { model.setStrictMode($0) }))
                } header: {
                    Text("Modo estricto")
                } footer: {
                    Text("Para desactivar o borrar horarios y límites, subir un límite, quitar apps de un perfil o quitar la protección contra borrado necesitarás tu llave NFC. Crear, añadir o endurecer sigue siendo libre. Desactivar este modo también pide la llave.")
                }

                Section {
                    Toggle("Impedir borrar apps", isOn: Binding(get: { model.preventAppRemoval }, set: { model.setPreventAppRemoval($0) }))
                } header: {
                    Text("Protección")
                } footer: {
                    Text("Mientras haya algo bloqueado, iOS no deja eliminar ninguna app, incluida FocusKey. Así no se puede saltar el bloqueo desinstalándola.")
                }

                Section {
                    Toggle("Live Activity", isOn: $model.liveActivities)
                    if model.liveActivities && !ActivityAuthorizationInfo().areActivitiesEnabled {
                        Button("Activar Actividades en directo en Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("Pantalla de bloqueo")
                } footer: {
                    Text("Muestra la cuenta atrás de las sesiones y los pomodoros en la pantalla de bloqueo y en la Dynamic Island.")
                }

                Section {
                    Toggle("Avisar antes de un límite", isOn: $model.limitWarnings)
                    if notificationsDenied && model.limitWarnings {
                        Button("Activar notificaciones en Ajustes") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("Avisos")
                } footer: {
                    Text("Recibirás una notificación cuando te queden 5 minutos de un límite (1 minuto en límites cortos).")
                }

                Section {
                    Label("Ajustes › Concentración › elige un modo › Filtros de concentración › FocusKey", systemImage: "moon.fill")
                        .font(.subheadline)
                } header: {
                    Text("Modos de concentración")
                } footer: {
                    Text("Al activar ese modo se bloquea el perfil que elijas. Al desactivarlo el bloqueo sigue: solo tu llave lo quita.")
                }

                Section {
                    LabeledContent("Texto de la etiqueta") {
                        Text(verbatim: NFCScanner.tagText)
                            .font(.body.monospaced())
                    }
                    Button(copied ? String(localized: "Copiado") : String(localized: "Copiar texto")) {
                        UIPasteboard.general.string = NFCScanner.tagText
                        copied = true
                    }
                } header: {
                    Text("Llave NFC")
                } footer: {
                    Text("Graba este texto en una etiqueta NFC (NDEF, registro de texto) con cualquier app de escritura NFC, como NFC Tools.")
                }

                Section {
                    ForEach(model.cardKeys) { card in
                        Button {
                            editingCard = card
                        } label: {
                            LabeledContent {
                                Text(card.added.formatted(date: .abbreviated, time: .omitted))
                            } label: {
                                Label(card.displayName, systemImage: "key.card")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { model.removeCard(model.cardKeys[index].id) }
                    }
                    if CardKey.canAdd(existing: model.cardKeys.count) {
                        Button("Añadir llave", systemImage: "plus") { addingCard = true }
                    } else if model.cardKeys.count > CardKey.maximum {
                        // Registered before the one-key rule: keep them working, but ask to trim.
                        Label("Solo debería haber una llave de repuesto. Elimina las que sobren.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Llave de repuesto")
                } footer: {
                    Text("Registra una etiqueta o tarjeta más (aunque no se pueda grabar, como la del metro) por si pierdes tu llave. Solo puede haber una, para no tener demasiadas formas de desbloquear: para cambiarla, elimínala y añade la nueva. Toca la llave para cambiarle el nombre. No se puede añadir mientras haya un bloqueo; con el modo estricto, añadirla pide tu llave.")
                }

                Section {
                    Button("Ver la introducción") { showingOnboarding = true }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = settings.authorizationStatus == .denied
            }
            .sheet(isPresented: $addingCard) { AddCardSheet() }
            .sheet(item: $editingCard) { EditCardSheet(card: $0) }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
        }
    }
}
