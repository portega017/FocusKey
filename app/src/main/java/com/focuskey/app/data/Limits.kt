package com.focuskey.app.data

import java.time.LocalDate
import java.util.UUID
import org.json.JSONObject

/** Blocks a profile for the rest of the day once its apps have been used for [minutes]. */
data class UsageLimit(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val profileId: String?,
    val minutes: Int = 30,
    val isEnabled: Boolean = true,
) {
    /** Minutes left when the warning is sent: 5 for limits of 15 min or more, 1 for shorter ones. */
    val warningLeadMinutes: Int?
        get() = when {
            minutes >= 15 -> 5
            minutes >= 3 -> 1
            else -> null
        }

    /** More minutes, another profile or turning it off all allow more use. */
    fun isWeakenedBy(new: UsageLimit): Boolean {
        if (!isEnabled) return false
        return !new.isEnabled || new.minutes > minutes || new.profileId != profileId
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("minutes", minutes)
        .put("isEnabled", isEnabled)
        .apply { profileId?.let { put("profileId", it) } }

    companion object {
        fun fromJson(json: JSONObject) = UsageLimit(
            id = json.getString("id"),
            name = json.optString("name", ""),
            profileId = json.optString("profileId", "").ifEmpty { null },
            minutes = json.optInt("minutes", 30),
            isEnabled = json.optBoolean("isEnabled", true),
        )
    }
}

/** Today's state of one limit: reached, and extra time granted with the tag. */
data class LimitDay(
    val date: LocalDate,
    val reached: Boolean = false,
    /** Usage (minutes) at which the extra time runs out; null when no extra time was granted. */
    val extendedUntil: Int? = null,
    val warned: Boolean = false,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("date", date.toString())
        .put("reached", reached)
        .put("warned", warned)
        .apply { extendedUntil?.let { put("extendedUntil", it) } }

    companion object {
        fun fromJson(json: JSONObject) = LimitDay(
            date = LocalDate.parse(json.getString("date")),
            reached = json.optBoolean("reached", false),
            extendedUntil = if (json.has("extendedUntil")) json.getInt("extendedUntil") else null,
            warned = json.optBoolean("warned", false),
        )
    }
}

/** One block, for statistics. */
data class BlockRecord(
    val id: String = UUID.randomUUID().toString(),
    val kind: Kind,
    val title: String,
    /** What produced it ("manual", or a schedule/limit id), used to close it. */
    val sourceId: String,
    val start: Long,
    val end: Long? = null,
) {
    enum class Kind { MANUAL, SESSION, SCHEDULE, LIMIT, POMODORO }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("kind", kind.name)
        .put("title", title)
        .put("sourceId", sourceId)
        .put("start", start)
        .apply { end?.let { put("end", it) } }

    companion object {
        fun fromJson(json: JSONObject) = BlockRecord(
            id = json.getString("id"),
            kind = runCatching { Kind.valueOf(json.getString("kind")) }.getOrDefault(Kind.MANUAL),
            title = json.optString("title", ""),
            sourceId = json.getString("sourceId"),
            start = json.getLong("start"),
            end = if (json.has("end")) json.getLong("end") else null,
        )
    }
}
