package com.focuskey.app.logic

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import com.focuskey.app.blocking.FocusAccessibilityService
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Selection
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Locking rules shared by the UI and the blocking service.
 *
 * There are two independent locks, as on iOS:
 *  - the manual lock (button / NFC tag);
 *  - the schedule lock, on while a schedule interval is running and hasn't been skipped with the tag.
 * Content is blocked if either lock includes it.
 */
object FocusEngine {

    /** Android equivalent of the Screen Time authorization: the accessibility service is on. */
    fun isAuthorized(context: Context): Boolean {
        val expected = ComponentName(context, FocusAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == expected
        }
    }

    fun isScheduleSkipped(skips: Map<String, Long>, schedule: Schedule, now: LocalDateTime): Boolean {
        val until = skips[schedule.id] ?: return false
        return until > now.toEpochMillis()
    }

    /** True while a schedule is running now and hasn't been skipped with the tag. */
    fun isScheduleBlocking(store: FocusStore, now: LocalDateTime = LocalDateTime.now()): Boolean {
        val skips = store.scheduleSkips
        return store.schedules.any { it.isActive(now) && !isScheduleSkipped(skips, it, now) }
    }

    /**
     * Starts or ends the schedule lock to match the schedules (what the DeviceActivityMonitor
     * extension does on iOS). Called by the service on every app change and by the UI periodically.
     */
    fun syncScheduleLock(store: FocusStore, now: LocalDateTime = LocalDateTime.now()) {
        val nowMillis = now.toEpochMillis()
        val skips = store.scheduleSkips
        val validSkips = skips.filterValues { it > nowMillis }
        if (validSkips.size != skips.size) store.scheduleSkips = validSkips

        val shouldBlock = isScheduleBlocking(store, now)
        if (shouldBlock && !store.isScheduleLocked) {
            val selection = store.selection
            if (selection.isEmpty) return
            // Snapshot at interval start, so editing the selection can't lift the block.
            store.scheduleShield = selection
            store.isScheduleLocked = true
        } else if (!shouldBlock && store.isScheduleLocked) {
            clearScheduleLock(store)
        }
    }

    /** Turns the manual lock on or off. Returns the status message to show. */
    fun setManualLock(context: Context, store: FocusStore, shouldLock: Boolean): String {
        if (!isAuthorized(context)) {
            return "Error: activa el servicio de bloqueo de FocusKey en Accesibilidad."
        }
        return if (shouldLock) {
            val selection = store.selection
            when {
                selection.isEmpty -> "Selecciona aplicaciones, categorías o dominios web para bloquear."
                store.isLocked -> "El bloqueo ya está activo."
                else -> {
                    store.manualShield = selection
                    store.isLocked = true
                    "Bloqueo activado."
                }
            }
        } else {
            if (!store.isLocked) {
                "El bloqueo ya está desactivado."
            } else {
                clearManualLock(store)
                "Bloqueo desactivado."
            }
        }
    }

    /**
     * The tag is the master key: if anything is blocking (manual lock or a running schedule),
     * it unlocks everything; otherwise it locks manually.
     */
    fun handleNfc(context: Context, store: FocusStore, now: LocalDateTime = LocalDateTime.now()): String {
        return if (store.isLocked || isScheduleBlocking(store, now)) {
            unlockWithTag(store, now)
        } else {
            setManualLock(context, store, true)
        }
    }

    private fun unlockWithTag(store: FocusStore, now: LocalDateTime): String {
        val active = store.schedules.filter { it.isActive(now) }

        if (active.isNotEmpty()) {
            // Skip each running schedule until its current interval ends; the next one blocks again.
            val nowMillis = now.toEpochMillis()
            val skips = store.scheduleSkips.filterValues { it > nowMillis }.toMutableMap()
            active.forEach { skips[it.id] = it.currentIntervalEnd(now).toEpochMillis() }
            store.scheduleSkips = skips
            clearScheduleLock(store)
        }

        if (store.isLocked) clearManualLock(store)

        return if (active.isEmpty()) "Bloqueo desactivado."
        else "Horario desbloqueado hasta el final del intervalo."
    }

    private fun clearManualLock(store: FocusStore) {
        store.isLocked = false
        store.manualShield = Selection()
    }

    private fun clearScheduleLock(store: FocusStore) {
        store.isScheduleLocked = false
        store.scheduleShield = Selection()
    }

    /** Selections currently enforced by the blocking service. */
    fun activeShields(store: FocusStore): List<Selection> = buildList {
        if (store.isLocked) add(store.manualShield)
        if (store.isScheduleLocked) add(store.scheduleShield)
    }

    private fun LocalDateTime.toEpochMillis(): Long =
        atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
}
