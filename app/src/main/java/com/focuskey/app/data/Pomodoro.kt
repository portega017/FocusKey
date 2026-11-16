package com.focuskey.app.data

import org.json.JSONObject

/**
 * Pomodoro: focus blocks with breaks in between. The engine compares the clock with the plan,
 * so blocking follows it exactly even if the app isn't running. Times are epoch millis.
 */
data class PomodoroPlan(
    val profileId: String,
    val start: Long,
    val focusMinutes: Int,
    val breakMinutes: Int,
    val cycles: Int,
) {
    sealed interface Phase {
        /** [cycle] is zero-based. */
        data class Focus(val cycle: Int, val start: Long, val end: Long) : Phase
        data class Rest(val cycle: Int, val start: Long, val end: Long) : Phase
        data object Finished : Phase
    }

    fun blockStart(cycle: Int): Long = start + cycle.toLong() * (focusMinutes + breakMinutes) * MINUTE
    fun blockEnd(cycle: Int): Long = blockStart(cycle) + focusMinutes * MINUTE

    /** End of the last focus block: there is no break after it. */
    val end: Long get() = blockEnd(cycles - 1)

    val totalFocusMinutes: Int get() = focusMinutes * cycles

    fun phase(at: Long): Phase {
        if (at < start) return Phase.Rest(-1, at, start)
        for (cycle in 0 until cycles) {
            if (at < blockEnd(cycle)) return Phase.Focus(cycle, blockStart(cycle), blockEnd(cycle))
            if (cycle < cycles - 1 && at < blockStart(cycle + 1)) {
                return Phase.Rest(cycle, blockEnd(cycle), blockStart(cycle + 1))
            }
        }
        return Phase.Finished
    }

    fun isFinished(at: Long): Boolean = phase(at) == Phase.Finished

    /** The same plan with the current break cut short: the next block starts at [at]. */
    fun skippingBreak(at: Long): PomodoroPlan? {
        val phase = phase(at) as? Phase.Rest ?: return null
        if (phase.cycle < 0 || phase.end <= at) return null
        return copy(start = start - (phase.end - at))
    }

    fun toJson(): JSONObject = JSONObject()
        .put("profileId", profileId)
        .put("start", start)
        .put("focusMinutes", focusMinutes)
        .put("breakMinutes", breakMinutes)
        .put("cycles", cycles)

    companion object {
        const val MINUTE = 60_000L
        val FOCUS_OPTIONS = listOf(25, 30, 45, 50, 60)
        val BREAK_OPTIONS = listOf(5, 10, 15, 20)
        val CYCLE_RANGE = 2..6

        fun fromJson(json: JSONObject) = PomodoroPlan(
            profileId = json.getString("profileId"),
            start = json.getLong("start"),
            focusMinutes = json.getInt("focusMinutes"),
            breakMinutes = json.getInt("breakMinutes"),
            cycles = json.getInt("cycles"),
        )
    }
}

/** A one-tap block: a timed session ("Social · 1 h") or a pomodoro ("Study · 4×25"). */
data class SessionPreset(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String = "",
    val profileId: String,
    /** Length of a timed session. Ignored for pomodoro presets. */
    val minutes: Int = 60,
    val pomodoro: PomodoroSettings? = null,
) {
    data class PomodoroSettings(val focusMinutes: Int = 25, val breakMinutes: Int = 5, val cycles: Int = 4)

    /** "4×25" for a pomodoro; sessions are formatted by the UI. */
    val pomodoroText: String? get() = pomodoro?.let { "${it.cycles}×${it.focusMinutes}" }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("profileId", profileId)
        .put("minutes", minutes)
        .apply {
            pomodoro?.let {
                put("pomodoro", JSONObject()
                    .put("focusMinutes", it.focusMinutes)
                    .put("breakMinutes", it.breakMinutes)
                    .put("cycles", it.cycles))
            }
        }

    companion object {
        val DURATION_OPTIONS = listOf(15, 30, 45, 60, 90, 120, 180, 240)

        fun fromJson(json: JSONObject) = SessionPreset(
            id = json.getString("id"),
            name = json.optString("name", ""),
            profileId = json.getString("profileId"),
            minutes = json.optInt("minutes", 60),
            pomodoro = json.optJSONObject("pomodoro")?.let {
                PomodoroSettings(it.optInt("focusMinutes", 25), it.optInt("breakMinutes", 5), it.optInt("cycles", 4))
            },
        )
    }
}
