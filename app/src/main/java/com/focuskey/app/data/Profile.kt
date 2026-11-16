package com.focuskey.app.data

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** A named set of apps, categories and websites to block. Same idea as FocusProfile on iOS. */
data class Profile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val icon: String = "shield",
    val colorName: String = "indigo",
    val selection: Selection = Selection(),
) {
    val isEmpty: Boolean get() = selection.isEmpty

    /** Whether replacing this profile with [new] lets something through (an app, category or site removed). */
    fun isWeakenedBy(new: Profile): Boolean =
        !new.selection.apps.containsAll(selection.apps) ||
            !new.selection.categories.containsAll(selection.categories) ||
            !new.selection.domains.containsAll(selection.domains)

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("icon", icon)
        .put("colorName", colorName)
        .put("apps", JSONArray(selection.apps.toList()))
        .put("categories", JSONArray(selection.categories.toList()))
        .put("domains", JSONArray(selection.domains.toList()))

    companion object {
        /** Icon keys shown in the profile editor (mapped to Material icons in the UI). */
        val ICONS = listOf(
            "shield", "work", "book", "bedtime", "games", "chat",
            "tv", "cart", "run", "restaurant", "school", "home",
        )

        /** Color names, in the order shown in the editor (same palette as iOS). */
        val COLORS = listOf("indigo", "blue", "teal", "green", "orange", "red", "pink", "purple", "brown", "gray")

        /** First color not used yet, so new profiles look different by default. */
        fun nextColor(profiles: List<Profile>): String {
            val used = profiles.map { it.colorName }.toSet()
            return COLORS.firstOrNull { it !in used } ?: COLORS[profiles.size % COLORS.size]
        }

        fun fromJson(json: JSONObject): Profile = Profile(
            id = json.getString("id"),
            name = json.optString("name", ""),
            icon = json.optString("icon", "shield"),
            colorName = json.optString("colorName", "indigo"),
            selection = Selection(
                apps = json.optJSONArray("apps").strings().toSet(),
                categories = json.optJSONArray("categories").ints().toSet(),
                domains = json.optJSONArray("domains").strings().toSet(),
            ),
        )
    }
}

internal fun JSONArray?.strings(): List<String> =
    if (this == null) emptyList() else (0 until length()).map { getString(it) }

internal fun JSONArray?.ints(): List<Int> =
    if (this == null) emptyList() else (0 until length()).map { getInt(it) }

/** Union of several selections (what a set of running blocks covers). */
fun List<Selection>.union(): Selection = Selection(
    apps = flatMap { it.apps }.toSet(),
    categories = flatMap { it.categories }.toSet(),
    domains = flatMap { it.domains }.toSet(),
)
