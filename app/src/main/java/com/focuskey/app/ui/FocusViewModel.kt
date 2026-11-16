package com.focuskey.app.ui

import android.app.Application
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.StringRes
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.focuskey.app.R
import com.focuskey.app.admin.FocusAdminReceiver
import com.focuskey.app.data.BlockRecord
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.LimitDay
import com.focuskey.app.data.PomodoroPlan
import com.focuskey.app.data.Profile
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Selection
import com.focuskey.app.data.SessionPreset
import com.focuskey.app.data.UsageLimit
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.logic.FocusEngine.toLocalDateTime
import com.focuskey.app.logic.LockError
import com.focuskey.app.logic.UsageTracker
import com.focuskey.app.nfc.NfcKeyReader
import com.focuskey.app.notify.FocusNotifications
import com.focuskey.app.notify.FocusUpdates
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Everything the screens, widget and tiles show, read in one go from the store. */
data class UiState(
    val now: Long,
    val profiles: List<Profile>,
    val activeProfileId: String?,
    val isLocked: Boolean,
    val manualProfileId: String?,
    val sessionStart: Long,
    val sessionEnd: Long,
    val schedules: List<Schedule>,
    val runningScheduleIds: Set<String>,
    val pomodoro: PomodoroPlan?,
    val presets: List<SessionPreset>,
    val limits: List<UsageLimit>,
    val limitDays: Map<String, LimitDay>,
    /** Minutes used today per enabled limit (refreshed every few seconds). */
    val limitUsage: Map<String, Int>,
    val blockingLimitIds: Set<String>,
    val records: List<BlockRecord>,
    val dailyArchive: Map<String, Int>,
    val archivedUntil: LocalDate?,
    val revocations: List<Long>,
    val strictMode: Boolean,
    val liveNotification: Boolean,
    val limitWarnings: Boolean,
    val preventRemoval: Boolean,
    val isAuthorized: Boolean,
    val hasUsageAccess: Boolean,
    val onboardingDone: Boolean,
) {
    fun profile(id: String?): Profile? = profiles.firstOrNull { it.id == id } ?: profiles.firstOrNull()
    val activeProfile: Profile? get() = profile(activeProfileId)
    val manualProfile: Profile? get() = if (isLocked) profile(manualProfileId) else null
    val runningSchedules: List<Schedule> get() = schedules.filter { it.id in runningScheduleIds }
    val hasSession: Boolean get() = isLocked && sessionEnd > now
    val pomodoroPhase: PomodoroPlan.Phase? get() = pomodoro?.phase(now)
    val isBlocked: Boolean get() = isLocked || runningScheduleIds.isNotEmpty() || blockingLimitIds.isNotEmpty()
    val canUnlockWithKey: Boolean get() = isLocked || pomodoro != null || runningScheduleIds.isNotEmpty()

    /** Revoked (service turned off after it had been on) and not turned on again yet. */
    val isRevoked: Boolean get() = !isAuthorized && revocations.isNotEmpty()

    /** Profile behind the current block (manual, then schedules, then limits). */
    val blockingProfile: Profile?
        get() = manualProfile
            ?: runningSchedules.firstOrNull()?.let { profile(it.profileId) }
            ?: limits.firstOrNull { it.id in blockingLimitIds }?.let { profile(it.profileId) }

    companion object {
        fun read(context: Context, store: FocusStore, limitUsage: Map<String, Int> = emptyMap(), now: Long = System.currentTimeMillis()): UiState {
            val active = store.activeProfileId
            val profiles = store.profiles
            return UiState(
                now = now,
                profiles = profiles,
                activeProfileId = profiles.firstOrNull { it.id == active }?.id ?: profiles.firstOrNull()?.id,
                isLocked = store.isLocked,
                manualProfileId = store.manualProfileId,
                sessionStart = store.sessionStart,
                sessionEnd = store.sessionEnd,
                schedules = store.schedules,
                runningScheduleIds = FocusEngine.runningSchedules(store, now).map { it.id }.toSet(),
                pomodoro = store.activePomodoro(now),
                presets = store.presets,
                limits = store.limits,
                limitDays = store.limitDays,
                limitUsage = limitUsage,
                blockingLimitIds = if (store.isLimitLocked) store.limitShieldIds else emptySet(),
                records = store.records,
                dailyArchive = store.dailyArchive,
                archivedUntil = store.archivedUntil,
                revocations = store.revocations,
                strictMode = store.strictMode,
                liveNotification = store.liveNotification,
                limitWarnings = store.limitWarnings,
                preventRemoval = store.preventRemoval,
                isAuthorized = FocusEngine.isAuthorized(context),
                hasUsageAccess = UsageTracker.hasAccess(context),
                onboardingDone = store.onboardingDone,
            )
        }
    }
}

/** Android equivalent of FocusModel on iOS. */
class FocusViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application
    private val store = FocusStore(application)
    private var limitUsage: Map<String, Int> = emptyMap()

    private val _state = MutableStateFlow(UiState.read(app, store))
    val state: StateFlow<UiState> = _state.asStateFlow()

    /** Last message for the user, shown as a snackbar. */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    // NFC scan dialog
    private val _nfcScanning = MutableStateFlow(false)
    val nfcScanning: StateFlow<Boolean> = _nfcScanning.asStateFlow()
    private val _nfcPrompt = MutableStateFlow<String?>(null)
    val nfcPrompt: StateFlow<String?> = _nfcPrompt.asStateFlow()
    private val _nfcError = MutableStateFlow<String?>(null)
    val nfcError: StateFlow<String?> = _nfcError.asStateFlow()

    /** Set by the activity. */
    var nfcAvailability: () -> NfcKeyReader.Availability = { NfcKeyReader.Availability.UNSUPPORTED }

    /** Runs instead of the default lock/unlock after the next valid tag (strict mode, pauses, extensions). */
    private var pendingKeyAction: (() -> Unit)? = null

    /** The blocking service and the UI share the same preferences: reload on any change. */
    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> reload() }

    init {
        store.prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        // Existing users who already picked apps don't need the walkthrough.
        if (!store.onboardingDone && store.profiles.any { !it.isEmpty }) store.onboardingDone = true
        viewModelScope.launch {
            var tick = 0
            while (true) {
                if (tick % 15 == 0) syncLimits()
                refresh()
                tick++
                delay(1_000)
            }
        }
    }

    override fun onCleared() {
        store.prefs.unregisterOnSharedPreferenceChangeListener(prefsListener)
    }

    private fun reload() {
        _state.value = UiState.read(app, store, limitUsage)
    }

    /** Syncs locks with the clock and reloads. Runs every second. */
    fun refresh() {
        if (FocusEngine.sync(store)) FocusUpdates.refreshAll(app)
        reload()
    }

    /** Called when the app comes to the foreground. */
    fun onResume() {
        checkAuthorization()
        syncPreventRemoval()
        syncLimits()
        refresh()
        FocusUpdates.refreshAll(app)
    }

    private fun syncLimits() {
        FocusEngine.syncLimits(app, store).forEach { (limit, left) -> FocusNotifications.limitWarning(app, limit, left) }
        limitUsage = FocusEngine.limitUsage(app, store)
    }

    /** After any change: sync, reload and keep the notification, widget and tiles in step. */
    private fun changed() {
        FocusEngine.sync(store)
        syncLimits()
        reload()
        FocusUpdates.refreshAll(app)
    }

    fun consumeMessage() {
        _message.value = null
    }

    fun say(@StringRes id: Int, vararg args: Any) {
        _message.value = app.getString(id, *args)
    }

    private fun describe(error: Throwable): String = when (error) {
        LockError.NotAuthorized -> app.getString(R.string.error_not_authorized)
        is LockError.EmptyProfile -> app.getString(R.string.error_empty_profile, error.name)
        LockError.AlreadyLocked -> app.getString(R.string.error_already_locked)
        LockError.PomodoroRunning -> app.getString(R.string.error_pomodoro_running)
        LockError.SessionTooShort -> app.getString(R.string.error_session_too_short, FocusEngine.MINIMUM_SESSION_MINUTES)
        LockError.NotExtendable -> app.getString(R.string.error_not_extendable)
        else -> error.localizedMessage.orEmpty()
    }

    // MARK: Authorization

    /** Notices when the blocking service was turned off, which lifts every block. */
    private fun checkAuthorization() {
        val authorized = FocusEngine.isAuthorized(app)
        if (authorized) {
            store.wasAuthorized = true
        } else if (store.wasAuthorized) {
            store.wasAuthorized = false
            store.logRevocation()
            say(R.string.revoked_message)
        }
    }

    // MARK: Strict mode

    /** In strict mode a weakening change waits for the NFC tag; otherwise it runs right away. */
    private fun guarded(weakening: Boolean, action: () -> Unit) {
        if (!store.strictMode || !weakening) {
            action()
            return
        }
        requireKey(app.getString(R.string.strict_confirm), action)
    }

    /** Asks for the tag, then runs [action]. */
    private fun requireKey(prompt: String, action: () -> Unit) {
        pendingKeyAction = action
        startNfcScan(prompt)
    }

    fun setStrictMode(enabled: Boolean) {
        if (enabled == store.strictMode) return
        guarded(!enabled) {
            store.strictMode = enabled
            say(if (enabled) R.string.strict_on else R.string.strict_off)
            changed()
        }
    }

    fun setLiveNotification(enabled: Boolean) {
        store.liveNotification = enabled
        changed()
    }

    fun setLimitWarnings(enabled: Boolean) {
        store.limitWarnings = enabled
        changed()
    }

    // MARK: Uninstall protection

    private val adminComponent get() = ComponentName(app, FocusAdminReceiver::class.java)

    private fun syncPreventRemoval() {
        val active = app.getSystemService(DevicePolicyManager::class.java).isAdminActive(adminComponent)
        if (store.preventRemoval != active) store.preventRemoval = active
    }

    /** Turning protection off needs the key in strict mode; turning it on happens in the system dialog. */
    fun disablePreventRemoval() {
        guarded(true) {
            app.getSystemService(DevicePolicyManager::class.java).removeActiveAdmin(adminComponent)
            store.preventRemoval = false
            changed()
        }
    }

    // MARK: Locking

    fun setActiveProfile(id: String) {
        store.activeProfileId = id
        changed()
    }

    fun lock(minutes: Int? = null, profileId: String? = null) {
        FocusEngine.lockManually(app, store, profileId ?: _state.value.activeProfileId, minutes)
            .onSuccess { profile ->
                if (minutes != null) say(R.string.msg_locked_for, profile.name, formatMinutes(app, minutes))
                else say(R.string.msg_locked, profile.name)
            }
            .onFailure { _message.value = describe(it) }
        changed()
    }

    fun extendSession(minutes: Int) {
        FocusEngine.extendSession(store, minutes)
            .onSuccess { say(R.string.msg_extended, formatClock(app, it)) }
            .onFailure { _message.value = describe(it) }
        changed()
    }

    fun startPomodoro(focusMinutes: Int, breakMinutes: Int, cycles: Int, profileId: String? = null) {
        FocusEngine.startPomodoro(app, store, profileId ?: _state.value.activeProfileId, focusMinutes, breakMinutes, cycles)
            .onSuccess { plan ->
                FocusNotifications.schedulePomodoro(app, plan)
                say(R.string.msg_pomodoro_started, plan.cycles, formatClock(app, plan.end))
            }
            .onFailure { _message.value = describe(it) }
        changed()
    }

    fun skipBreak() {
        val plan = FocusEngine.skipBreak(store) ?: return
        FocusNotifications.schedulePomodoro(app, plan)
        say(R.string.msg_break_skipped)
        changed()
    }

    // MARK: NFC

    fun startNfcScan(prompt: String? = null) {
        when (nfcAvailability()) {
            NfcKeyReader.Availability.UNSUPPORTED -> {
                pendingKeyAction = null
                say(R.string.nfc_unsupported)
            }
            NfcKeyReader.Availability.DISABLED -> {
                pendingKeyAction = null
                say(R.string.nfc_disabled)
            }
            NfcKeyReader.Availability.AVAILABLE -> {
                _nfcPrompt.value = prompt
                _nfcError.value = null
                _nfcScanning.value = true
            }
        }
    }

    fun cancelNfcScan() {
        pendingKeyAction = null
        _nfcScanning.value = false
    }

    fun onTagRead(isValidKey: Boolean) {
        if (!_nfcScanning.value) return
        if (!isValidKey) {
            _nfcError.value = app.getString(R.string.nfc_invalid)
            return
        }
        _nfcScanning.value = false
        val pending = pendingKeyAction
        pendingKeyAction = null
        if (pending != null) pending() else handleKey()
    }

    /** The tag lifts the manual lock, a pomodoro and running schedules; otherwise it locks. Never limits. */
    private fun handleKey() {
        if (!FocusEngine.canUnlockWithKey(store)) {
            if (store.isLimitLocked) return say(R.string.key_limits_stay)
            lock()
            return
        }
        val result = FocusEngine.unlockWithKey(store)
        if (result.pomodoro) FocusNotifications.cancelPomodoro(app)
        val parts = buildList {
            if (result.pomodoro) add(app.getString(R.string.key_pomodoro_ended))
            if (result.manual) add(app.getString(R.string.key_manual_off))
            if (result.schedules > 0) add(app.getString(R.string.key_schedule_skipped))
            if (store.isLimitLocked) add(app.getString(R.string.key_limits_remain))
        }
        _message.value = if (parts.isEmpty()) app.getString(R.string.key_nothing)
        else parts.joinToString(", ").replaceFirstChar { it.uppercase() } + "."
        changed()
    }

    // MARK: Profiles

    /** Why the profile's apps can't change right now, or null if they can. */
    fun profileLockReason(id: String): String? {
        val state = _state.value
        return when {
            state.manualProfile?.id == id -> app.getString(R.string.profile_locked_manual)
            state.pomodoro?.profileId == id -> app.getString(R.string.profile_locked_pomodoro)
            state.runningSchedules.any { state.profile(it.profileId)?.id == id } -> app.getString(R.string.profile_locked_schedule)
            state.limits.any { it.id in state.blockingLimitIds && state.profile(it.profileId)?.id == id } ->
                app.getString(R.string.profile_locked_limit)
            else -> null
        }
    }

    fun saveProfile(profile: Profile) {
        val profiles = store.profiles
        val existing = profiles.firstOrNull { it.id == profile.id }
        if (existing == null) {
            store.profiles = profiles + profile
            changed()
            return
        }
        if (existing.selection != profile.selection) {
            profileLockReason(profile.id)?.let { _message.value = it; return }
        }
        guarded(existing.isWeakenedBy(profile)) {
            store.profiles = store.profiles.map { if (it.id == profile.id) profile else it }
            changed()
        }
    }

    fun deleteProfile(id: String) {
        val profiles = store.profiles
        if (profiles.size <= 1) return say(R.string.profile_need_one)
        profileLockReason(id)?.let { _message.value = it; return }
        if (store.schedules.any { store.profile(it.profileId, profiles)?.id == id } ||
            store.limits.any { store.profile(it.profileId, profiles)?.id == id }
        ) {
            return say(R.string.profile_used)
        }
        store.profiles = profiles.filterNot { it.id == id }
        // A "1 h of Social" preset makes no sense with another profile.
        store.presets = store.presets.filterNot { it.profileId == id }
        changed()
    }

    // MARK: Presets

    fun startPreset(preset: SessionPreset) {
        val pomodoro = preset.pomodoro
        if (pomodoro != null) {
            startPomodoro(pomodoro.focusMinutes, pomodoro.breakMinutes, pomodoro.cycles, preset.profileId)
        } else {
            lock(preset.minutes, preset.profileId)
        }
    }

    fun savePreset(preset: SessionPreset) {
        val presets = store.presets
        store.presets = if (presets.any { it.id == preset.id }) presets.map { if (it.id == preset.id) preset else it }
        else presets + preset
        changed()
    }

    fun deletePreset(id: String) {
        store.presets = store.presets.filterNot { it.id == id }
        changed()
    }

    // MARK: Limits

    private fun isLimitBlocking(id: String) = id in _state.value.blockingLimitIds

    fun saveLimit(limit: UsageLimit) {
        val limits = store.limits
        val existing = limits.firstOrNull { it.id == limit.id }
        if (existing == null) {
            store.limits = limits + limit
            changed()
            return
        }
        if (isLimitBlocking(limit.id)) return say(R.string.limit_reached_locked)
        guarded(existing.isWeakenedBy(limit)) {
            store.limits = store.limits.map { if (it.id == limit.id) limit else it }
            changed()
        }
    }

    fun setLimitEnabled(id: String, enabled: Boolean) {
        val existing = store.limits.firstOrNull { it.id == id } ?: return
        saveLimit(existing.copy(isEnabled = enabled))
    }

    fun deleteLimit(id: String) {
        val limit = store.limits.firstOrNull { it.id == id } ?: return
        if (isLimitBlocking(id)) return say(R.string.limit_reached_locked)
        guarded(limit.isEnabled) {
            store.limits = store.limits.filterNot { it.id == id }
            store.limitDays = store.limitDays - id
            changed()
        }
    }

    /** Extra time on reached limits always needs the tag. */
    fun extendLimits(minutes: Int) {
        requireKey(app.getString(R.string.extend_limit_prompt)) {
            val count = FocusEngine.extendLimits(app, store, minutes)
            if (count == 0) say(R.string.no_limit_reached) else say(R.string.limit_extended, formatMinutes(app, minutes))
            changed()
        }
    }

    // MARK: Schedules

    fun saveSchedule(schedule: Schedule) {
        val schedules = store.schedules
        val existing = schedules.firstOrNull { it.id == schedule.id }
        if (existing == null) {
            store.schedules = schedules + schedule
            changed()
            return
        }
        // A running schedule can't be changed at all.
        if (existing != schedule && existing.isActive()) return say(R.string.schedule_running_locked)
        guarded(existing.isWeakenedBy(schedule)) {
            store.schedules = store.schedules.map { if (it.id == schedule.id) schedule else it }
            changed()
        }
    }

    fun setScheduleEnabled(id: String, enabled: Boolean) {
        val existing = store.schedules.firstOrNull { it.id == id } ?: return
        if (existing.isActive()) return say(R.string.schedule_running_locked)
        saveSchedule(existing.copy(isEnabled = enabled))
    }

    fun deleteSchedule(id: String) {
        val schedule = store.schedules.firstOrNull { it.id == id } ?: return
        if (schedule.isActive()) return say(R.string.schedule_running_locked)
        guarded(schedule.isEnabled) {
            store.schedules = store.schedules.filterNot { it.id == id }
            changed()
        }
    }

    fun duplicateSchedule(id: String) {
        val schedule = store.schedules.firstOrNull { it.id == id } ?: return
        store.schedules = store.schedules + schedule.copy(
            id = UUID.randomUUID().toString(),
            name = if (schedule.name.isEmpty()) "" else app.getString(R.string.copy_of, schedule.name),
            pausedDays = emptySet(),
        )
        changed()
    }

    /** Skips the interval that starts on [day] (needs the tag in strict mode). */
    fun pauseSchedule(id: String, day: LocalDate) {
        val schedule = store.schedules.firstOrNull { it.id == id } ?: return
        if (!schedule.intervalStart(day).isAfter(System.currentTimeMillis().toLocalDateTime())) {
            return say(R.string.pause_already_started)
        }
        guarded(schedule.isEnabled) {
            store.schedules = store.schedules.map {
                if (it.id == id) it.copy(pausedDays = it.activePauses().toSet() + day) else it
            }
            say(R.string.pause_done, schedule.name.ifEmpty { app.getString(R.string.schedule_default_name) }, formatDay(day))
            changed()
        }
    }

    /** Cancels a pause. No key needed: it only makes things stricter. */
    fun resumeSchedule(id: String, day: LocalDate) {
        store.schedules = store.schedules.map {
            if (it.id == id) it.copy(pausedDays = it.pausedDays - day) else it
        }
        changed()
    }

    // MARK: Onboarding

    /** Strict mode chosen in the walkthrough is applied at the end, so changing your mind is free. */
    fun finishOnboarding(strictMode: Boolean) {
        if (strictMode) store.strictMode = true
        store.onboardingDone = true
        changed()
    }

    fun setActiveProfileSelection(selection: Selection) {
        val profile = store.profile(store.activeProfileId) ?: return
        store.profiles = store.profiles.map { if (it.id == profile.id) it.copy(selection = selection) else it }
        changed()
    }
}
