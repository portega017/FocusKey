package com.focuskey.app.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent state shared by the app UI, the blocking service and the alarm receiver
 * (Android equivalent of the App Group UserDefaults on iOS).
 */
class FocusStore(context: Context) {
    val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // MARK: Profiles

    /** Saved profiles. The first read after updating migrates the old single selection. */
    var profiles: List<Profile>
        get() {
            val saved = readList(PROFILES, Profile::fromJson)
            if (saved.isNotEmpty()) return saved
            val initial = listOf(Profile(name = DEFAULT_PROFILE_NAME, selection = readSelection(LEGACY_SELECTION)))
            profiles = initial
            return initial
        }
        set(value) = writeList(PROFILES, value) { it.toJson() }

    /** The profile with this id, or the first one when [id] is null or no longer exists. */
    fun profile(id: String?, all: List<Profile> = profiles): Profile? =
        all.firstOrNull { it.id == id } ?: all.firstOrNull()

    var activeProfileId: String?
        get() = prefs.getString(ACTIVE_PROFILE, null)
        set(value) = prefs.edit().putString(ACTIVE_PROFILE, value).apply()

    // MARK: Manual lock (button / NFC / sessions / pomodoro blocks). Independent from schedules.

    var isLocked: Boolean
        get() = prefs.getBoolean(LOCKED, false)
        set(value) = prefs.edit().putBoolean(LOCKED, value).apply()

    var manualProfileId: String?
        get() = prefs.getString(MANUAL_PROFILE, null)
        set(value) = prefs.edit().putString(MANUAL_PROFILE, value).apply()

    /** What the manual lock blocks: a snapshot of the profile taken when it was turned on. */
    var manualShield: Selection
        get() = readSelection(MANUAL_SHIELD)
        set(value) = writeSelection(MANUAL_SHIELD, value)

    /** Start and end of a timed session (epoch millis); 0 for an indefinite lock. */
    var sessionStart: Long
        get() = prefs.getLong(SESSION_START, 0)
        set(value) = prefs.edit().putLong(SESSION_START, value).apply()

    var sessionEnd: Long
        get() = prefs.getLong(SESSION_END, 0)
        set(value) = prefs.edit().putLong(SESSION_END, value).apply()

    // MARK: Schedule lock, set while a schedule interval is running.

    var isScheduleLocked: Boolean
        get() = prefs.getBoolean(SCHEDULE_LOCKED, false)
        set(value) = prefs.edit().putBoolean(SCHEDULE_LOCKED, value).apply()

    var scheduleShield: Selection
        get() = readSelection(SCHEDULE_SHIELD)
        set(value) = writeSelection(SCHEDULE_SHIELD, value)

    /** Ids of the schedules covered by [scheduleShield], to notice when the set changes. */
    var scheduleShieldIds: Set<String>
        get() = prefs.getStringSet(SCHEDULE_SHIELD_IDS, emptySet())!!.toSet()
        set(value) = prefs.edit().putStringSet(SCHEDULE_SHIELD_IDS, value).apply()

    // MARK: Schedules

    var schedules: List<Schedule>
        get() = readList(SCHEDULES, Schedule::fromJson)
        set(value) = writeList(SCHEDULES, value) { it.toJson() }

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

    // MARK: Pomodoro and presets

    var pomodoro: PomodoroPlan?
        get() = prefs.getString(POMODORO, null)?.let { runCatching { PomodoroPlan.fromJson(JSONObject(it)) }.getOrNull() }
        set(value) {
            if (value == null) prefs.edit().remove(POMODORO).apply()
            else prefs.edit().putString(POMODORO, value.toJson().toString()).apply()
        }

    /** The pomodoro plan if it hasn't finished yet. */
    fun activePomodoro(now: Long = System.currentTimeMillis()): PomodoroPlan? =
        pomodoro?.takeUnless { it.isFinished(now) }

    var presets: List<SessionPreset>
        get() = readList(PRESETS, SessionPreset::fromJson)
        set(value) = writeList(PRESETS, value) { it.toJson() }

    // MARK: Usage limits

    var limits: List<UsageLimit>
        get() = readList(LIMITS, UsageLimit::fromJson)
        set(value) = writeList(LIMITS, value) { it.toJson() }

    /** Limit id -> today's state. Entries from other days are ignored. */
    var limitDays: Map<String, LimitDay>
        get() {
            val raw = prefs.getString(LIMIT_DAYS, null) ?: return emptyMap()
            return runCatching {
                val json = JSONObject(raw)
                json.keys().asSequence().associateWith { LimitDay.fromJson(json.getJSONObject(it)) }
            }.getOrDefault(emptyMap())
        }
        set(value) {
            val json = JSONObject()
            value.forEach { (id, day) -> json.put(id, day.toJson()) }
            prefs.edit().putString(LIMIT_DAYS, json.toString()).apply()
        }

    var isLimitLocked: Boolean
        get() = prefs.getBoolean(LIMIT_LOCKED, false)
        set(value) = prefs.edit().putBoolean(LIMIT_LOCKED, value).apply()

    var limitShield: Selection
        get() = readSelection(LIMIT_SHIELD)
        set(value) = writeSelection(LIMIT_SHIELD, value)

    /** Ids of the limits currently blocking, to open and close statistics records. */
    var limitShieldIds: Set<String>
        get() = prefs.getStringSet(LIMIT_SHIELD_IDS, emptySet())!!.toSet()
        set(value) = prefs.edit().putStringSet(LIMIT_SHIELD_IDS, value).apply()

    // MARK: Statistics

    var records: List<BlockRecord>
        get() = readList(RECORDS, BlockRecord::fromJson)
        private set(value) = writeList(RECORDS, value) { it.toJson() }

    fun openRecord(kind: BlockRecord.Kind, title: String, sourceId: String, at: Long = System.currentTimeMillis()) {
        val all = records
        // Never keep two open records for the same source.
        if (all.any { it.sourceId == sourceId && it.end == null }) return
        saveRecords(all + BlockRecord(kind = kind, title = title, sourceId = sourceId, start = at), at)
    }

    fun closeRecords(sourceId: String, at: Long = System.currentTimeMillis()) {
        val all = records
        if (all.none { it.sourceId == sourceId && it.end == null }) return
        saveRecords(all.map { if (it.sourceId == sourceId && it.end == null) it.copy(end = maxOf(at, it.start)) else it }, at)
    }

    /** Saves records, first folding whole days older than 60 days into [dailyArchive]. */
    private fun saveRecords(all: List<BlockRecord>, now: Long) {
        val zone = java.time.ZoneId.systemDefault()
        val boundary = java.time.Instant.ofEpochMilli(now - MAX_RECORD_AGE).atZone(zone).toLocalDate()
        val boundaryMillis = boundary.atStartOfDay(zone).toInstant().toEpochMilli()
        if (all.any { (it.end ?: now) < boundaryMillis }) {
            val counter = com.focuskey.app.logic.DayCounter(all, now = now)
            var day = archivedUntil ?: all.minOf { it.start }.let { java.time.Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }
            val archive = dailyArchive.toMutableMap()
            while (day < boundary) {
                val minutes = counter.minutes(day)
                if (minutes > 0) archive[day.toString()] = minutes
                day = day.plusDays(1)
            }
            dailyArchive = archive
            archivedUntil = boundary
        }
        records = all.filter { (it.end ?: now) >= boundaryMillis }
    }

    /** "2026-11-08" -> minutes, for days whose records were pruned. */
    var dailyArchive: Map<String, Int>
        get() {
            val raw = prefs.getString(DAILY_ARCHIVE, null) ?: return emptyMap()
            return runCatching {
                val json = JSONObject(raw)
                json.keys().asSequence().associateWith { json.getInt(it) }
            }.getOrDefault(emptyMap())
        }
        private set(value) = prefs.edit().putString(DAILY_ARCHIVE, JSONObject(value).toString()).apply()

    /** Days before this one are read from [dailyArchive] only. */
    var archivedUntil: java.time.LocalDate?
        get() = prefs.getString(ARCHIVED_UNTIL, null)?.let { runCatching { java.time.LocalDate.parse(it) }.getOrNull() }
        private set(value) = prefs.edit().putString(ARCHIVED_UNTIL, value?.toString()).apply()

    // MARK: Authorization

    /** Accessibility service seen on at the last check, to notice when it gets turned off. */
    var wasAuthorized: Boolean
        get() = prefs.getBoolean(WAS_AUTHORIZED, false)
        set(value) = prefs.edit().putBoolean(WAS_AUTHORIZED, value).apply()

    /** Moments the blocking service was found turned off (last 60 days). */
    val revocations: List<Long>
        get() = prefs.getString(REVOCATIONS, null)?.split(',')?.mapNotNull { it.toLongOrNull() } ?: emptyList()

    fun logRevocation(at: Long = System.currentTimeMillis()) {
        val kept = (revocations + at).filter { it > at - MAX_RECORD_AGE }
        prefs.edit().putString(REVOCATIONS, kept.joinToString(",")).apply()
    }

    // MARK: Settings

    /** Strict mode: loosening schedules, profiles or this setting needs the NFC tag. */
    var strictMode: Boolean
        get() = prefs.getBoolean(STRICT_MODE, false)
        set(value) = prefs.edit().putBoolean(STRICT_MODE, value).apply()

    /** Ongoing countdown notification for sessions and pomodoros (on by default). */
    var liveNotification: Boolean
        get() = prefs.getBoolean(LIVE_NOTIFICATION, true)
        set(value) = prefs.edit().putBoolean(LIVE_NOTIFICATION, value).apply()

    /** While anything is blocked, the device-admin screen is blocked too, so FocusKey can't be uninstalled. */
    var preventRemoval: Boolean
        get() = prefs.getBoolean(PREVENT_REMOVAL, false)
        set(value) = prefs.edit().putBoolean(PREVENT_REMOVAL, value).apply()

    /** Notify a few minutes before a daily limit is reached (on by default). */
    var limitWarnings: Boolean
        get() = prefs.getBoolean(LIMIT_WARNINGS, true)
        set(value) = prefs.edit().putBoolean(LIMIT_WARNINGS, value).apply()

    var onboardingDone: Boolean
        get() = prefs.getBoolean(ONBOARDING_DONE, false)
        set(value) = prefs.edit().putBoolean(ONBOARDING_DONE, value).apply()

    // MARK: Helpers

    private fun <T> readList(key: String, parse: (JSONObject) -> T): List<T> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { runCatching { parse(array.getJSONObject(it)) }.getOrNull() }
        }.getOrDefault(emptyList())
    }

    private fun <T> writeList(key: String, value: List<T>, toJson: (T) -> JSONObject) {
        val array = JSONArray().apply { value.forEach { put(toJson(it)) } }
        prefs.edit().putString(key, array.toString()).apply()
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
        /** Name of the profile created from the old single selection (not translated: it's data). */
        const val DEFAULT_PROFILE_NAME = "General"

        /** Single selection used before profiles existed; migrated into the first profile. */
        const val LEGACY_SELECTION = "selection"
        const val PROFILES = "profiles"
        const val ACTIVE_PROFILE = "activeProfile"
        const val LOCKED = "isLocked"
        const val MANUAL_PROFILE = "manualProfile"
        const val MANUAL_SHIELD = "manualShield"
        const val SESSION_START = "sessionStart"
        const val SESSION_END = "sessionEnd"
        const val SCHEDULE_LOCKED = "isScheduleLocked"
        const val SCHEDULE_SHIELD = "scheduleShield"
        const val SCHEDULE_SHIELD_IDS = "scheduleShieldIds"
        const val SCHEDULES = "schedules"
        const val SCHEDULE_SKIPS = "scheduleSkips"
        const val POMODORO = "pomodoro"
        const val PRESETS = "sessionPresets"
        const val STRICT_MODE = "strictMode"
        const val LIVE_NOTIFICATION = "liveNotification"
        const val LIMITS = "limits"
        const val LIMIT_DAYS = "limitDays"
        const val LIMIT_LOCKED = "isLimitLocked"
        const val LIMIT_SHIELD = "limitShield"
        const val LIMIT_SHIELD_IDS = "limitShieldIds"
        const val RECORDS = "blockRecords"
        const val DAILY_ARCHIVE = "dailyArchive"
        const val ARCHIVED_UNTIL = "archivedUntil"
        const val WAS_AUTHORIZED = "wasAuthorized"
        const val REVOCATIONS = "revocations"
        const val PREVENT_REMOVAL = "preventRemoval"
        const val LIMIT_WARNINGS = "limitWarnings"
        const val ONBOARDING_DONE = "onboardingDone"
        const val MAX_RECORD_AGE = 60L * 24 * 60 * 60 * 1000
    }
}
