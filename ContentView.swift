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
    @State private var showingSettings = false

    private static let sessionOptions = [15, 30, 60, 120, 240]

    var body: some View {
        NavigationStack {
            // Re-evaluated every 30 s so the state follows schedules, limits and sessions.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let status = FocusStatus.current(at: context.date)
                let tint = (status.blockingProfile ?? model.activeProfile)?.color ?? .indigo

                ScrollView {
                    VStack(spacing: 20) {
                        statusCard(status, tint: tint)

                        if !FocusLock.isAuthorized {
                            Button("Autorizar Screen Time") {
                                Task { await model.authorize() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(tint)
                        }

                        profileSection(tint: tint)

                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .background { background(tint: tint, blocked: status.isBlocked) }
                .animation(.smooth(duration: 0.6), value: status.isBlocked)
                .animation(.smooth, value: model.activeProfileID)
                .sensoryFeedback(trigger: status.isBlocked) { _, blocked in
                    blocked ? .impact(weight: .heavy) : .success
                }
            }
            .navigationTitle("FocusKey")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .task { await model.authorize() }
            .sheet(isPresented: $showingCustomSession) {
                CustomSessionSheet { minutes in model.lock(minutes: minutes) }
            }
        }
    }

    // MARK: Background

    /// Soft wash of the profile color behind the glass cards; stronger while blocked.
    private func background(tint: Color, blocked: Bool) -> some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [tint.opacity(blocked ? 0.35 : 0.18), tint.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Status

    private func statusCard(_ status: FocusStatus, tint: Color) -> some View {
        VStack(spacing: 18) {
            LockRing(status: status, tint: tint)

            VStack(spacing: 4) {
                Text(status.headline)
                    .font(.title2.bold())
                    .contentTransition(.opacity)
                if let detail = status.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(tint)
            }

            if !status.isManualLocked {
                lockButtons(tint: tint)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func lockButtons(tint: Color) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    model.lock()
                } label: {
                    Label("Bloquear", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)

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
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }

    // MARK: Profile

    private func profileSection(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perfil para bloquear")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.profiles) { profile in
                        ProfileChip(profile: profile, isSelected: profile.id == model.activeProfileID) {
                            model.activeProfileID = profile.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(model.isLocked)
            .opacity(model.isLocked ? 0.5 : 1)

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
            .buttonStyle(.glass)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

// MARK: - Lock ring

/// Lock symbol inside a ring: full while blocked, draining during a timed session.
private struct LockRing: View {
    let status: FocusStatus
    let tint: Color

    var body: some View {
        // Ticks every second only while a session runs.
        TimelineView(.periodic(from: .now, by: status.sessionEnd == nil ? 3600 : 1)) { context in
            let progress = status.sessionProgress(at: context.date)
            let remaining = progress.map { 1 - $0 } ?? (status.isBlocked ? 1 : 0)

            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.8), value: remaining)

                VStack(spacing: 6) {
                    Image(systemName: status.isBlocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(status.isBlocked ? tint : .green)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: status.isBlocked)

                    if let end = status.sessionEnd {
                        Text(end, style: .timer)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 170, height: 170)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.headline)
            .accessibilityValue(status.detail ?? "")
        }
    }
}

// MARK: - Profile chip

private struct ProfileChip: View {
    let profile: FocusProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(profile.displayName, systemImage: profile.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : profile.color)
                .background(isSelected ? profile.color : profile.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
