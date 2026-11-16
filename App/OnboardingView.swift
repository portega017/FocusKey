//
//  OnboardingView.swift
//  FocusKey
//
//  First-launch walkthrough: Screen Time permission, first profile, NFC key and notifications.
//

import SwiftUI
import FamilyControls

struct OnboardingView: View {
    @EnvironmentObject private var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingView.doneKey) private var done = false
    @State private var page = 0
    @State private var authorized = FocusLock.isAuthorized
    @State private var showingPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var copied = false
    /// Applied when the walkthrough ends, so changing your mind here never asks for the key.
    @State private var wantsStrictMode = false

    static let doneKey = "FocusKey.onboardingDone"
    private let lastPage = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                permission.tag(1)
                profile.tag(2)
                key.tag(3)
                sessions.tag(4)
                strict.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < lastPage ? String(localized: "Continuar") : String(localized: "Empezar"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in
            guard var profile = model.activeProfile else { return }
            profile.selection = newValue
            model.updateProfile(profile)
        }
        .onAppear { selection = model.activeProfile?.selection ?? .init() }
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(
            symbol: "lock.shield.fill",
            title: "Bienvenido a FocusKey",
            text: "Bloquear las apps que te distraen es fácil. Para desbloquearlas necesitas tu llave NFC: tendrás que levantarte a por ella."
        )
    }

    private var permission: some View {
        OnboardingPage(
            symbol: "hourglass",
            title: "Acceso a Tiempo de uso",
            text: "FocusKey usa Tiempo de uso de Apple para bloquear apps. Tus datos no salen del iPhone."
        ) {
            if authorized {
                Label("Acceso concedido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button("Permitir acceso") {
                    Task {
                        await model.authorize()
                        authorized = FocusLock.isAuthorized
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    private var profile: some View {
        OnboardingPage(
            symbol: "apps.iphone",
            title: "¿Qué quieres bloquear?",
            text: "Elige apps, categorías o webs para tu primer perfil. Luego podrás crear más perfiles, como Trabajo o Noche."
        ) {
            VStack(spacing: 8) {
                Button("Elegir apps") { showingPicker = true }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(!authorized)
                Text(model.activeProfile?.summary ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var key: some View {
        OnboardingPage(
            symbol: "wave.3.right",
            title: "Prepara tu llave",
            text: "Graba este texto en una etiqueta NFC con una app como NFC Tools y déjala lejos del móvil, por ejemplo en otra habitación."
        ) {
            VStack(spacing: 8) {
                Text(verbatim: NFCScanner.tagText)
                    .font(.title3.monospaced().bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                Button(copied ? String(localized: "Copiado") : String(localized: "Copiar texto")) {
                    UIPasteboard.general.string = NFCScanner.tagText
                    copied = true
                }
            }
        }
    }

    private var sessions: some View {
        OnboardingPage(
            symbol: "bolt.fill",
            title: "Sesiones rápidas y pomodoro",
            text: "Crea botones como «Redes · 1 h» o «Estudio · 4×25» para bloquear con un toque. También puedes usarlos con Siri o desde el Centro de Control."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sesión: un perfil durante un tiempo fijo", systemImage: "timer")
                Label("Pomodoro: bloques de concentración con descansos", systemImage: "timer.circle")
                Label("Horarios y límites diarios, automáticos", systemImage: "calendar.badge.clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var strict: some View {
        OnboardingPage(
            symbol: "key.fill",
            title: "Modo estricto",
            text: "Si lo activas, para relajar un bloqueo (desactivar un horario, subir un límite, quitar apps de un perfil…) necesitarás tu llave. Endurecer siempre es libre."
        ) {
            Toggle("Activar modo estricto", isOn: $wantsStrictMode)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }
    }

    private func finish() {
        if wantsStrictMode { model.setStrictMode(true) }
        if model.limitWarnings { model.requestNotificationPermission() }
        done = true
        dismiss()
    }
}

private struct OnboardingPage<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 116, height: 116)
                .background(Color.accentColor.gradient, in: Circle())
                .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 8)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            accessory
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

extension OnboardingPage where Accessory == EmptyView {
    init(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) {
        self.init(symbol: symbol, title: title, text: text) { EmptyView() }
    }
}
