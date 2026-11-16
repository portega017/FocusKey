package com.focuskey.app.admin

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import com.focuskey.app.data.FocusStore

/**
 * Device admin with no policies: while it's active Android won't uninstall FocusKey, and the
 * blocking service hides the screen that deactivates it whenever something is blocked.
 * Android equivalent of iOS `denyAppRemoval`.
 */
class FocusAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        FocusStore(context).preventRemoval = true
    }

    override fun onDisabled(context: Context, intent: Intent) {
        FocusStore(context).preventRemoval = false
    }
}
