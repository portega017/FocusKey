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

    static let doneKey = "FocusKey.onboardingDone"
    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                permission.tag(1)
                profile.tag(2)
                key.tag(3)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
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
                .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
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

    private func finish() {
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
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
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
