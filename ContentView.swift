//
//  ContentView.swift
//  FocusKey
//
//

import SwiftUI
import FamilyControls

struct ContentView: View {
    @EnvironmentObject private var model: FocusModel
    @EnvironmentObject private var nfc: NFCScanner
    @State private var showingCustomSession = false

    private static let sessionOptions = [15, 30, 60, 120, 240]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Re-evaluated every 30 s so the state follows schedules, limits and sessions.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        statusCard(FocusStatus.current(at: context.date))
                    }

                    if !FocusLock.isAuthorized {
                        Button("Autorizar Screen Time") {
                            Task { await model.authorize() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    profileSection

                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("FocusKey")
            .task { await model.authorize() }
            .sheet(isPresented: $showingCustomSession) {
                CustomSessionSheet { minutes in model.lock(minutes: minutes) }
            }
        }
    }

    // MARK: Status

    private func statusCard(_ status: FocusStatus) -> some View {
        VStack(spacing: 16) {
            Image(systemName: status.isBlocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(status.isBlocked ? .red : .green)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 4) {
                Text(status.headline)
                    .font(.title2.bold())
                if let detail = status.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let end = status.sessionEnd {
                    Text(end, style: .timer)
                        .font(.largeTitle.monospacedDigit().bold())
                        .padding(.top, 4)
                }
            }

            if !status.limits.isEmpty {
                ExtendLimitButton()
                    .controlSize(.large)
            }

            if status.canUnlockWithKey {
                Button {
                    nfc.start()
                } label: {
                    Label("Desbloquear con llave", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
            }

            if !status.isManualLocked {
                lockButtons
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var lockButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.lock()
            } label: {
                Label("Bloquear", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Menu {
                ForEach(Self.sessionOptions, id: \.self) { minutes in
                    Button(UsageLimit.formatted(minutes: minutes)) { model.lock(minutes: minutes) }
                }
                Divider()
                Button("Otra duración…") { showingCustomSession = true }
            } label: {
                Label("Durante…", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    // MARK: Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perfil para bloquear")
                .font(.headline)

            Picker("Perfil", selection: $model.activeProfileID) {
                ForEach(model.profiles) { profile in
                    Label(profile.displayName, systemImage: profile.symbol).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isLocked)

            if let profile = model.activeProfile {
                Text(profile.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                ProfilesView()
            } label: {
                Label("Gestionar perfiles", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Custom session

private struct CustomSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 45
    let onStart: (Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $minutes, in: FocusLock.minimumSessionMinutes...720, step: 5) {
                        Text(UsageLimit.formatted(minutes: minutes))
                            .font(.title3.monospacedDigit())
                    }
                } footer: {
                    Text("Se desbloquea solo al terminar, o antes con tu llave NFC. Mínimo \(FocusLock.minimumSessionMinutes) minutos.")
                }
            }
            .navigationTitle("Sesión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") {
                        onStart(minutes)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
