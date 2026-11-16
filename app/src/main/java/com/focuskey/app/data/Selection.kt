package com.focuskey.app.data

import android.content.Context
import android.content.pm.ApplicationInfo
import androidx.annotation.StringRes
import com.focuskey.app.R

/**
 * What to block: apps (package names), app categories (ApplicationInfo.CATEGORY_* values)
 * and web domains. Android equivalent of FamilyActivitySelection.
 */
data class Selection(
    val apps: Set<String> = emptySet(),
    val categories: Set<Int> = emptySet(),
    val domains: Set<String> = emptySet(),
) {
    val isEmpty: Boolean get() = apps.isEmpty() && categories.isEmpty() && domains.isEmpty()
}

/** App categories Android exposes (the closest thing to Screen Time categories). */
enum class AppCategory(val id: Int, @StringRes val label: Int) {
    SOCIAL(ApplicationInfo.CATEGORY_SOCIAL, R.string.category_social),
    GAME(ApplicationInfo.CATEGORY_GAME, R.string.category_games),
    VIDEO(ApplicationInfo.CATEGORY_VIDEO, R.string.category_video),
    AUDIO(ApplicationInfo.CATEGORY_AUDIO, R.string.category_audio),
    NEWS(ApplicationInfo.CATEGORY_NEWS, R.string.category_news),
    IMAGE(ApplicationInfo.CATEGORY_IMAGE, R.string.category_image),
    MAPS(ApplicationInfo.CATEGORY_MAPS, R.string.category_maps),
    PRODUCTIVITY(ApplicationInfo.CATEGORY_PRODUCTIVITY, R.string.category_productivity);

    companion object {
        fun labelFor(context: Context, id: Int): String =
            context.getString(entries.firstOrNull { it.id == id }?.label ?: R.string.category_other)
    }
}

/** Normalizes user input like "https://www.YouTube.com/watch" to "youtube.com". */
fun normalizeDomain(input: String): String? {
    val host = input.trim().lowercase()
        .substringAfter("://")
        .substringBefore('/')
        .substringBefore('?')
        .substringBefore(':')
        .removePrefix("www.")
        .trim('.')
    return host.takeIf { it.contains('.') && it.none(Char::isWhitespace) }
}

/** True if [host] is [domain] or one of its subdomains. */
fun hostMatches(host: String, domain: String): Boolean =
    host == domain || host.endsWith(".$domain")
