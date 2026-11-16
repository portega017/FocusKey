package com.focuskey.app.logic

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import com.focuskey.app.blocking.FocusAccessibilityService
import com.focuskey.app.data.BlockRecord
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.LimitDay
import com.focuskey.app.data.UsageLimit
import com.focuskey.app.data.PomodoroPlan
import com.focuskey.app.data.Profile
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Selection
import com.focuskey.app.data.union
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** Why a lock action couldn't happen. The UI turns these into messages. */
sealed class LockError : Exception() {
    data object NotAuthorized : LockError()
    data class EmptyProfile(val name: String) : LockError()
    data object AlreadyLocked : LockError()
    data object PomodoroRunning : LockError()
    data object SessionTooShort : LockError()
    data object NotExtendable : LockError()
}

/**
 * Locking rules shared by the UI, the blocking service and the alarm receiver.
 *
 * Independent blocking sources, as on iOS:
 *  - the manual lock (button / NFC / timed session / pomodoro focus block), on one profile;
 *  - the schedule lock: the union of the profiles of running, non-skipped schedules.
 * Everything is driven by the clock in [sync], so blocking is exact even if the app isn't open.
 */
object FocusEngine {

    const val MINIMUM_SESSION_MINUTES = 15
    private const val MANUAL_SOURCE = "manual"

    /** Android equivalent of the Screen Time authorization: the accessibility service is on. */
    fun isAuthorized(context: Context): Boolean {
        val expected = ComponentName(context, FocusAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == expected }
    }

    // MARK: Clock-driven state

    /**
     * Brings every lock in line with the clock: pomodoro phases, finished sessions and schedules.
     * Called by the service on app changes, by the UI periodically and by pomodoro alarms.
     */
    fun sync(store: FocusStore, now: Long = System.currentTimeMillis()): Boolean {
        val before = signature(store)
        if (store.pomodoro != null) {
            syncPomodoro(store, now)
        } else if (store.isLocked && store.sessionEnd in 1..now) {
            clearManualLock(store, at = store.sessionEnd)
        }
        syncScheduleLock(store, now)
        return signature(store) != before
    }

    /** What the widget, tiles and countdown show; changes mean they need refreshing. */
    private fun signature(store: FocusStore): List<Any?> = listOf(
        store.isLocked, store.sessionEnd, store.isScheduleLocked, store.scheduleShieldIds,
        store.isLimitLocked, store.limitShieldIds, store.pomodoro?.start,
    )

    fun isScheduleSkipped(skips: Map<String, Long>, schedule: Schedule, now: Long): Boolean =
        (skips[schedule.id] ?: 0L) > now

    /** Schedules running now and not skipped with the tag. */
    fun runningSchedules(store: FocusStore, now: Long = System.currentTimeMillis()): List<Schedule> {
        val skips = store.scheduleSkips
        val time = now.toLocalDateTime()
        return store.schedules.filter { it.isActive(time) && !isScheduleSkipped(skips, it, now) }
    }

    /** Starts, updates or ends the schedule lock (what the DeviceActivityMonitor does on iOS). */
    private fun syncScheduleLock(store: FocusStore, now: Long) {
        val skips = store.scheduleSkips
        val validSkips = skips.filterValues { it > now }
        if (validSkips.size != skips.size) store.scheduleSkips = validSkips

        val running = runningSchedules(store, now)
        val ids = running.map { it.id }.toSet()
        // Statistics: one record per running schedule.
        val previous = if (store.isScheduleLocked) store.scheduleShieldIds else emptySet()
        (previous - ids).forEach { store.closeRecords(it, now) }
        running.filter { it.id !in previous }.forEach {
            store.openRecord(BlockRecord.Kind.SCHEDULE, it.name.ifEmpty { "" }, it.id, now)
        }
        if (ids.isEmpty()) {
            if (store.isScheduleLocked) clearScheduleLock(store)
            return
        }
        if (store.isScheduleLocked && ids == store.scheduleShieldIds) return
        val profiles = store.profiles
        val shield = running.mapNotNull { store.profile(it.profileId, profiles)?.selection }.union()
        if (shield.isEmpty) {
            clearScheduleLock(store)
            return
        }
        store.scheduleShield = shield
        store.scheduleShieldIds = ids
        store.isScheduleLocked = true
    }

    // MARK: Manual lock and sessions

    /** Locks a profile until the tag is used, or for [minutes] when given. */
    fun lockManually(
        context: Context,
        store: FocusStore,
        profileId: String?,
        minutes: Int? = null,
        now: Long = System.currentTimeMillis(),
    ): Result<Profile> {
        if (!isAuthorized(context)) return Result.failure(LockError.NotAuthorized)
        if (store.isLocked) return Result.failure(LockError.AlreadyLocked)
        if (store.activePomodoro(now) != null) return Result.failure(LockError.PomodoroRunning)
        val profile = store.profile(profileId) ?: return Result.failure(LockError.EmptyProfile(""))
        if (profile.isEmpty) return Result.failure(LockError.EmptyProfile(profile.name))
        if (minutes != null && minutes < MINIMUM_SESSION_MINUTES) return Result.failure(LockError.SessionTooShort)

        applyManual(
            store, profile,
            start = if (minutes != null) now else 0,
            end = minutes?.let { now + it * PomodoroPlan.MINUTE } ?: 0,
            kind = if (minutes != null) BlockRecord.Kind.SESSION else BlockRecord.Kind.MANUAL,
            now = now,
        )
        return Result.success(profile)
    }

    /** Adds time to the running timed session. Stricter, so no tag needed. */
    fun extendSession(store: FocusStore, minutes: Int, now: Long = System.currentTimeMillis()): Result<Long> {
        val end = store.sessionEnd
        if (!store.isLocked || store.pomodoro != null || end <= now) return Result.failure(LockError.NotExtendable)
        val newEnd = end + minutes * PomodoroPlan.MINUTE
        store.sessionEnd = newEnd
        return Result.success(newEnd)
    }

    private fun applyManual(store: FocusStore, profile: Profile, start: Long, end: Long, kind: BlockRecord.Kind, now: Long) {
        store.openRecord(kind, profile.name, MANUAL_SOURCE, now)
        store.manualShield = profile.selection
        store.manualProfileId = profile.id
        store.sessionStart = start
        store.sessionEnd = end
        store.isLocked = true
    }

    private fun clearManualLock(store: FocusStore, at: Long = System.currentTimeMillis()) {
        store.closeRecords(MANUAL_SOURCE, at)
        store.isLocked = false
        store.manualProfileId = null
        store.manualShield = Selection()
        store.sessionStart = 0
        store.sessionEnd = 0
    }

    private fun clearScheduleLock(store: FocusStore) {
        store.isScheduleLocked = false
        store.scheduleShield = Selection()
        store.scheduleShieldIds = emptySet()
    }

    // MARK: Pomodoro

    fun startPomodoro(
        context: Context,
        store: FocusStore,
        profileId: String?,
        focusMinutes: Int,
        breakMinutes: Int,
        cycles: Int,
        now: Long = System.currentTimeMillis(),
    ): Result<PomodoroPlan> {
        if (!isAuthorized(context)) return Result.failure(LockError.NotAuthorized)
        if (store.isLocked) return Result.failure(LockError.AlreadyLocked)
        if (store.activePomodoro(now) != null) return Result.failure(LockError.PomodoroRunning)
        val profile = store.profile(profileId) ?: return Result.failure(LockError.EmptyProfile(""))
        if (profile.isEmpty) return Result.failure(LockError.EmptyProfile(profile.name))
        if (focusMinutes < MINIMUM_SESSION_MINUTES) return Result.failure(LockError.SessionTooShort)

        val plan = PomodoroPlan(
            profileId = profile.id,
            start = now,
            focusMinutes = focusMinutes,
            breakMinutes = breakMinutes.coerceAtLeast(1),
            cycles = cycles.coerceIn(PomodoroPlan.CYCLE_RANGE),
        )
        store.pomodoro = plan
        syncPomodoro(store, now)
        return Result.success(plan)
    }

    /** Locked during focus blocks, free during breaks, cleared when the plan is over. */
    fun syncPomodoro(store: FocusStore, now: Long = System.currentTimeMillis()) {
        val plan = store.pomodoro ?: return
        when (val phase = plan.phase(now)) {
            is PomodoroPlan.Phase.Focus -> {
                // While a pomodoro exists no other manual lock can start, so the manual lock is ours.
                if (!store.isLocked || store.sessionEnd != phase.end) {
                    val profile = store.profile(plan.profileId) ?: return
                    // The monitor missed the end of the previous block: don't count the break.
                    if (store.isLocked) store.closeRecords(MANUAL_SOURCE, minOf(store.sessionEnd, now))
                    applyManual(store, profile, phase.start, phase.end, BlockRecord.Kind.POMODORO, now)
                }
            }
            is PomodoroPlan.Phase.Rest -> if (store.isLocked) clearManualLock(store)
            PomodoroPlan.Phase.Finished -> endPomodoro(store)
        }
    }

    /** Starts the next focus block now. Stricter, so no tag needed. */
    fun skipBreak(store: FocusStore, now: Long = System.currentTimeMillis()): PomodoroPlan? {
        val shifted = store.pomodoro?.skippingBreak(now) ?: return null
        store.pomodoro = shifted
        syncPomodoro(store, now)
        return shifted
    }

    fun endPomodoro(store: FocusStore) {
        if (store.pomodoro == null) return
        store.pomodoro = null
        if (store.isLocked) clearManualLock(store)
    }

    // MARK: NFC master key

    data class KeyResult(val manual: Boolean, val pomodoro: Boolean, val schedules: Int) {
        val isEmpty: Boolean get() = !manual && !pomodoro && schedules == 0
    }

    /** The tag lifts the manual lock, a pomodoro and running schedules. */
    fun canUnlockWithKey(store: FocusStore, now: Long = System.currentTimeMillis()): Boolean =
        store.isLocked || store.activePomodoro(now) != null || runningSchedules(store, now).isNotEmpty()

    fun unlockWithKey(store: FocusStore, now: Long = System.currentTimeMillis()): KeyResult {
        val running = runningSchedules(store, now)
        if (running.isNotEmpty()) {
            // Skip each running schedule until its current interval ends; the next one blocks again.
            val skips = store.scheduleSkips.filterValues { it > now }.toMutableMap()
            val time = now.toLocalDateTime()
            running.forEach {
                skips[it.id] = it.currentIntervalEnd(time).toEpochMillis()
                store.closeRecords(it.id, now)
            }
            store.scheduleSkips = skips
            clearScheduleLock(store)
        }
        val pomodoro = store.pomodoro != null
        if (pomodoro) endPomodoro(store)
        val manual = store.isLocked
        if (manual) clearManualLock(store)
        return KeyResult(manual = manual, pomodoro = pomodoro, schedules = running.size)
    }

    /** Selections currently enforced by the blocking service. */
    fun activeShields(store: FocusStore): List<Selection> = buildList {
        if (store.isLocked) add(store.manualShield)
        if (store.isScheduleLocked) add(store.scheduleShield)
        if (store.isLimitLocked) add(store.limitShield)
    }

    /** Anything blocking (manual, schedules or reached limits). */
    fun isBlocked(store: FocusStore): Boolean = store.isLocked || store.isScheduleLocked || store.isLimitLocked

    // MARK: Daily limits

    /** Today's usage (minutes) per enabled limit. One query to UsageStatsManager for all of them. */
    fun limitUsage(context: Context, store: FocusStore, now: Long = System.currentTimeMillis()): Map<String, Int> {
        val limits = store.limits.filter { it.isEnabled }
        if (limits.isEmpty() || !UsageTracker.hasAccess(context)) return emptyMap()
        val start = java.time.LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val usage = UsageTracker.usageByPackage(context, start, now)
        val profiles = store.profiles
        return limits.associate { limit ->
            val selection = store.profile(limit.profileId, profiles)?.selection ?: Selection()
            limit.id to (usage.filterKeys { UsageTracker.matches(context, selection, it) }.values.sum() / 60_000).toInt()
        }
    }

    /** Whether a limit blocks today: reached and any extra time used up. */
    fun isLimitBlocking(day: LimitDay?, usage: Int, today: java.time.LocalDate): Boolean {
        if (day == null || day.date != today || !day.reached) return false
        val extra = day.extendedUntil ?: return true
        return usage >= extra
    }

    /**
     * Marks limits reached, sends the "almost there" warnings and applies the limit shield.
     * Returns the limits to warn about (with minutes left). Called by the service (≤ every 30 s)
     * and the app.
     */
    fun syncLimits(context: Context, store: FocusStore, now: Long = System.currentTimeMillis()): List<Pair<UsageLimit, Int>> {
        val today = java.time.LocalDate.now()
        val usage = limitUsage(context, store, now)
        val previous = store.limitDays
        val days = mutableMapOf<String, LimitDay>()
        val warnings = mutableListOf<Pair<UsageLimit, Int>>()
        val blocking = mutableListOf<UsageLimit>()
        for (limit in store.limits.filter { it.isEnabled }) {
            val used = usage[limit.id] ?: continue
            var day = previous[limit.id]?.takeIf { it.date == today } ?: LimitDay(today)
            val lead = limit.warningLeadMinutes
            if (!day.warned && !day.reached && lead != null && used >= limit.minutes - lead && used < limit.minutes) {
                day = day.copy(warned = true)
                warnings += limit to (limit.minutes - used)
            }
            if (!day.reached && used >= limit.minutes) day = day.copy(reached = true, warned = true)
            days[limit.id] = day
            if (isLimitBlocking(day, used, today)) blocking += limit
        }
        if (days != previous) store.limitDays = days

        val ids = blocking.map { it.id }.toSet()
        val before = if (store.isLimitLocked) store.limitShieldIds else emptySet()
        (before - ids).forEach { store.closeRecords(it, now) }
        blocking.filter { it.id !in before }.forEach { store.openRecord(BlockRecord.Kind.LIMIT, it.name, it.id, now) }
        if (ids != before || store.isLimitLocked != ids.isNotEmpty()) {
            val profiles = store.profiles
            store.limitShield = blocking.mapNotNull { store.profile(it.profileId, profiles)?.selection }.union()
            store.limitShieldIds = ids
            store.isLimitLocked = ids.isNotEmpty()
        }
        return warnings
    }

    /** Grants [minutes] of extra use to every reached limit (after a valid tag). */
    fun extendLimits(context: Context, store: FocusStore, minutes: Int, now: Long = System.currentTimeMillis()): Int {
        val today = java.time.LocalDate.now()
        val usage = limitUsage(context, store, now)
        val days = store.limitDays.toMutableMap()
        var count = 0
        for ((id, day) in days) {
            val used = usage[id] ?: continue
            if (isLimitBlocking(day, used, today)) {
                days[id] = day.copy(extendedUntil = used + minutes)
                count++
            }
        }
        store.limitDays = days
        syncLimits(context, store, now)
        return count
    }

    // MARK: Time helpers

    fun Long.toLocalDateTime(): LocalDateTime =
        LocalDateTime.ofInstant(Instant.ofEpochMilli(this), ZoneId.systemDefault())

    fun LocalDateTime.toEpochMillis(): Long = atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
}
