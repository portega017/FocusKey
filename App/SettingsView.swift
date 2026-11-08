//
//  SettingsView.swift
//  FocusKey
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false
    @State private var showingOnboarding = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Impedir borrar apps", isOn: $model.preventAppRemoval)
                } header: {
                    Text("Protección")
                } footer: {
                    Text("Mientras haya algo bloqueado, iOS no deja eliminar ninguna app, incluida FocusKey. Así no se puede saltar el bloqueo desinstalándola.")
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
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
        }
    }
}
