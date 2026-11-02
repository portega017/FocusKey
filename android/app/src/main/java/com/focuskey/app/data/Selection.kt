package com.focuskey.app.data

import android.content.pm.ApplicationInfo

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
enum class AppCategory(val id: Int, val label: String) {
    SOCIAL(ApplicationInfo.CATEGORY_SOCIAL, "Redes sociales"),
    GAME(ApplicationInfo.CATEGORY_GAME, "Juegos"),
    VIDEO(ApplicationInfo.CATEGORY_VIDEO, "Vídeo y entretenimiento"),
    AUDIO(ApplicationInfo.CATEGORY_AUDIO, "Música y audio"),
    NEWS(ApplicationInfo.CATEGORY_NEWS, "Noticias y revistas"),
    IMAGE(ApplicationInfo.CATEGORY_IMAGE, "Fotos e imágenes"),
    MAPS(ApplicationInfo.CATEGORY_MAPS, "Mapas y navegación"),
    PRODUCTIVITY(ApplicationInfo.CATEGORY_PRODUCTIVITY, "Productividad");

    companion object {
        fun labelFor(id: Int): String = entries.firstOrNull { it.id == id }?.label ?: "Otra"
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
