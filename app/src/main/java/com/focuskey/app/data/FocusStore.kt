package com.focuskey.app.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent state shared by the app UI and the blocking service
 * (Android equivalent of the App Group UserDefaults on iOS).
 */
class FocusStore(context: Context) {
    val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // MARK: Selection chosen by the user

    var selection: Selection
        get() = readSelection(SELECTION)
        set(value) = writeSelection(SELECTION, value)

    // MARK: Manual lock (button / NFC). Independent from schedules.

    var isLocked: Boolean
        get() = prefs.getBoolean(LOCKED, false)
        set(value) = prefs.edit().putBoolean(LOCKED, value).apply()

    /** What the manual lock blocks: a snapshot of the selection taken when it was turned on. */
    var manualShield: Selection
        get() = readSelection(MANUAL_SHIELD)
        set(value) = writeSelection(MANUAL_SHIELD, value)

    // MARK: Schedule lock, set while a schedule interval is running.

    var isScheduleLocked: Boolean
        get() = prefs.getBoolean(SCHEDULE_LOCKED, false)
        set(value) = prefs.edit().putBoolean(SCHEDULE_LOCKED, value).apply()

    var scheduleShield: Selection
        get() = readSelection(SCHEDULE_SHIELD)
        set(value) = writeSelection(SCHEDULE_SHIELD, value)

    // MARK: Schedules

    var schedules: List<Schedule>
        get() {
            val raw = prefs.getString(SCHEDULES, null) ?: return emptyList()
            return runCatching {
                val array = JSONArray(raw)
                (0 until array.length()).map { Schedule.fromJson(array.getJSONObject(it)) }
            }.getOrDefault(emptyList())
        }
        set(value) {
            val array = JSONArray().apply { value.forEach { put(it.toJson()) } }
            prefs.edit().putString(SCHEDULES, array.toString()).apply()
        }

    /** Schedules skipped with the NFC tag: schedule id -> end of the skipped interval (epoch millis). */
    var scheduleSkips: Map<String, Long>
        get() {
            val raw = prefs.getString(SCHEDULE_SKIPS, null) ?: return emptyMap()
            return runCatching {
                val json = JSONObject(raw)
                json.keys().asSequence().associateWith { json.getLong(it) }
            }.getOrDefault(emptyMap())
        }
        set(value) {
            prefs.edit().putString(SCHEDULE_SKIPS, JSONObject(value).toString()).apply()
        }

    private fun readSelection(prefix: String) = Selection(
        apps = prefs.getStringSet("$prefix.apps", emptySet())!!.toSet(),
        categories = prefs.getStringSet("$prefix.categories", emptySet())!!
            .mapNotNull(String::toIntOrNull).toSet(),
        domains = prefs.getStringSet("$prefix.domains", emptySet())!!.toSet(),
    )

    private fun writeSelection(prefix: String, value: Selection) {
        prefs.edit()
            .putStringSet("$prefix.apps", value.apps)
            .putStringSet("$prefix.categories", value.categories.map(Int::toString).toSet())
            .putStringSet("$prefix.domains", value.domains)
            .apply()
    }

    companion object {
        const val PREFS_NAME = "focuskey"
        const val SELECTION = "selection"
        const val LOCKED = "isLocked"
        const val MANUAL_SHIELD = "manualShield"
        const val SCHEDULE_LOCKED = "isScheduleLocked"
        const val SCHEDULE_SHIELD = "scheduleShield"
        const val SCHEDULES = "schedules"
        const val SCHEDULE_SKIPS = "scheduleSkips"
    }
}
