package com.focuskey.app.blocking

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.hostMatches
import com.focuskey.app.data.normalizeDomain
import com.focuskey.app.logic.FocusEngine

/**
 * Watches which app (and, in browsers, which website) is on screen and covers it with
 * [BlockedActivity] while a lock includes it. Android equivalent of ManagedSettings shields.
 */
class FocusAccessibilityService : AccessibilityService() {

    private lateinit var store: FocusStore
    private val categoryCache = mutableMapOf<String, Int>()
    private var lastSync = 0L
    private var lastBlock = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        store = FocusStore(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString() ?: return
        if (packageName == this.packageName || packageName in IGNORED_PACKAGES) return

        // Keep the schedule lock in step with the clock (at most every few seconds).
        val now = SystemClock.elapsedRealtime()
        if (now - lastSync > SYNC_INTERVAL_MS) {
            lastSync = now
            FocusEngine.syncScheduleLock(store)
        }

        val shields = FocusEngine.activeShields(store)
        if (shields.isEmpty()) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val category = categoryOf(packageName)
            if (shields.any { packageName in it.apps || (category != null && category in it.categories) }) {
                block(packageName, isWebsite = false)
                return
            }
        }

        val urlBarIds = BROWSER_URL_BARS[packageName] ?: return
        val domains = shields.flatMap { it.domains }
        if (domains.isEmpty()) return
        val host = currentHost(urlBarIds) ?: return
        val blockedDomain = domains.firstOrNull { hostMatches(host, it) } ?: return
        block(blockedDomain, isWebsite = true)
    }

    override fun onInterrupt() = Unit

    private fun block(target: String, isWebsite: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastBlock < BLOCK_DEBOUNCE_MS) return
        lastBlock = now

        // Leave the blocked page/app so going back doesn't return to it.
        performGlobalAction(if (isWebsite) GLOBAL_ACTION_BACK else GLOBAL_ACTION_HOME)
        startActivity(
            Intent(this, BlockedActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(BlockedActivity.EXTRA_TARGET, target)
                .putExtra(BlockedActivity.EXTRA_IS_WEBSITE, isWebsite)
        )
    }

    private fun categoryOf(packageName: String): Int? {
        categoryCache[packageName]?.let { return it.takeIf { c -> c != ApplicationInfo.CATEGORY_UNDEFINED } }
        val category = try {
            packageManager.getApplicationInfo(packageName, 0).category
        } catch (e: PackageManager.NameNotFoundException) {
            ApplicationInfo.CATEGORY_UNDEFINED
        }
        categoryCache[packageName] = category
        return category.takeIf { it != ApplicationInfo.CATEGORY_UNDEFINED }
    }

    /** Reads the address bar of a supported browser, unless the user is typing in it. */
    private fun currentHost(urlBarIds: List<String>): String? {
        val root = rootInActiveWindow ?: return null
        for (id in urlBarIds) {
            val node: AccessibilityNodeInfo = root.findAccessibilityNodeInfosByViewId(id).firstOrNull() ?: continue
            if (node.isFocused) return null
            val text = node.text?.toString() ?: continue
            return normalizeDomain(text)
        }
        return null
    }

    companion object {
        private const val SYNC_INTERVAL_MS = 5_000L
        private const val BLOCK_DEBOUNCE_MS = 1_500L

        private val IGNORED_PACKAGES = setOf("com.android.systemui")

        /** Address bar view ids of common browsers. */
        private val BROWSER_URL_BARS: Map<String, List<String>> = mapOf(
            "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
            "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
            "com.chrome.dev" to listOf("com.chrome.dev:id/url_bar"),
            "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
            "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
            "com.kiwibrowser.browser" to listOf("com.kiwibrowser.browser:id/url_bar"),
            "com.vivaldi.browser" to listOf("com.vivaldi.browser:id/url_bar"),
            "org.mozilla.firefox" to listOf(
                "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
                "org.mozilla.firefox:id/url_bar_title"
            ),
            "org.mozilla.focus" to listOf("org.mozilla.focus:id/mozac_browser_toolbar_url_view"),
            "com.sec.android.app.sbrowser" to listOf(
                "com.sec.android.app.sbrowser:id/location_bar_edit_text",
                "com.sec.android.app.sbrowser:id/url_bar_text"
            ),
            "com.opera.browser" to listOf("com.opera.browser:id/url_field"),
            "com.opera.mini.native" to listOf("com.opera.mini.native:id/url_field"),
            "com.duckduckgo.mobile.android" to listOf("com.duckduckgo.mobile.android:id/omnibarTextInput"),
        )
    }
}
