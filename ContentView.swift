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
    @State private var showingPomodoro = false
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
                        if model.isAuthorizationRevoked {
                            revokedBanner
                        }

                        statusCard(status, tint: tint)

                        if !model.isAuthorized {
                            Button("Autorizar Screen Time") {
                                Task { await model.authorize() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(tint)
                        }

                        PresetGrid(isDisabled: status.isManualLocked || status.pomodoro != nil)

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
            .sheet(isPresented: $showingPomodoro) {
                PomodoroSheet(profile: model.activeProfile) { focus, rest, cycles in
                    model.startPomodoro(focusMinutes: focus, breakMinutes: rest, cycles: cycles)
                }
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

    // MARK: Revoked permission

    private var revokedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Screen Time está desactivado", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Se retiró el permiso de FocusKey en Ajustes, así que ahora no se bloquea nada. Autorízalo de nuevo y se restaurarán tus bloqueos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let last = model.revocations.last {
                Text("Última vez: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 28))
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
                    Label(
                        status.pomodoro != nil ? String(localized: "Terminar con llave") : String(localized: "Desbloquear con llave"),
                        systemImage: "wave.3.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(tint)
            }

            if !status.isManualLocked && status.pomodoro == nil {
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
                    Button("Pomodoro…", systemImage: "timer.circle") { showingPomodoro = true }
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
            .disabled(model.isLocked || model.pomodoro != nil)
            .opacity(model.isLocked || model.pomodoro != nil ? 0.5 : 1)

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

/// Lock symbol inside a ring: full while blocked, draining during a timed session or a
/// pomodoro break.
private struct LockRing: View {
    let status: FocusStatus
    let tint: Color

    /// A pomodoro break shown in the ring when nothing else is blocked.
    private var rest: (start: Date, end: Date)? {
        guard !status.isBlocked, case let .rest(_, start, end)? = status.pomodoroPhase else { return nil }
        return (start, end)
    }

    var body: some View {
        // Ticks every second only while a session or a break runs.
        TimelineView(.periodic(from: .now, by: status.sessionEnd == nil && rest == nil ? 3600 : 1)) { context in
            let restProgress = rest.map { min(1, max(0, context.date.timeIntervalSince($0.start) / $0.end.timeIntervalSince($0.start))) }
            let progress = status.sessionProgress(at: context.date) ?? restProgress
            let remaining = progress.map { 1 - $0 } ?? (status.isBlocked ? 1 : 0)
            let ringTint: Color = rest == nil ? tint : .green

            ZStack {
                Circle()
                    .stroke(ringTint.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(ringTint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.8), value: remaining)

                VStack(spacing: 6) {
                    Image(systemName: rest != nil ? "cup.and.saucer.fill" : (status.isBlocked ? "lock.fill" : "lock.open.fill"))
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(status.isBlocked ? tint : .green)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: status.isBlocked)

                    if let end = status.sessionEnd ?? rest?.end {
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

// MARK: - Pomodoro

private struct PomodoroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var cycles = 4
    let profile: FocusProfile?
    let onStart: (Int, Int, Int) -> Void

    private var plan: PomodoroPlan {
        PomodoroPlan(profileID: profile?.id ?? UUID(), start: .now, focusMinutes: focusMinutes, breakMinutes: breakMinutes, cycles: cycles)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Concentración", selection: $focusMinutes) {
                        ForEach(PomodoroPlan.focusOptions, id: \.self) { Text(UsageLimit.formatted(minutes: $0)).tag($0) }
                    }
                    Picker("Descanso", selection: $breakMinutes) {
                        ForEach(PomodoroPlan.breakOptions, id: \.self) { Text(UsageLimit.formatted(minutes: $0)).tag($0) }
                    }
                    Stepper(value: $cycles, in: PomodoroPlan.cycleRange) {
                        Text("\(cycles) ciclos")
                    }
                } footer: {
                    Text("Durante cada bloque se bloquea «\(profile?.displayName ?? "")». En los descansos tus apps quedan libres. Tu llave NFC termina el pomodoro antes de tiempo.")
                }

                Section {
                    LabeledContent("Concentración total", value: UsageLimit.formatted(minutes: plan.totalFocusMinutes))
                    LabeledContent("Termina a las", value: plan.end.formatted(date: .omitted, time: .shortened))
                }
            }
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") {
                        onStart(focusMinutes, breakMinutes, cycles)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
