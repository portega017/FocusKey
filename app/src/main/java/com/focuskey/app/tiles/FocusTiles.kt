package com.focuskey.app.tiles

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.focuskey.app.R
import com.focuskey.app.data.FocusStore
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.notify.FocusUpdates
import com.focuskey.app.ui.MainActivity

/** Opens FocusKey, optionally starting an NFC scan right away. */
@SuppressLint("StartActivityAndCollapseDeprecated")
internal fun TileService.openApp(scan: Boolean) {
    val intent = Intent(this, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .putExtra(MainActivity.EXTRA_SCAN, scan)
    if (Build.VERSION.SDK_INT >= 34) {
        startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
    } else {
        @Suppress("DEPRECATION")
        startActivityAndCollapse(intent)
    }
}

/**
 * Quick Settings "Lock" (Control Center equivalent): locks the selected profile. When something
 * is already blocked it opens FocusKey to use the key — there is no unlock without it.
 */
class LockTileService : TileService() {
    override fun onStartListening() {
        val tile = qsTile ?: return
        val blocked = FocusEngine.isBlocked(FocusStore(this))
        tile.state = if (blocked) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(if (blocked) R.string.status_locked else R.string.lock)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_notification)
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = getString(R.string.app_name)
        tile.updateTile()
    }

    override fun onClick() {
        val store = FocusStore(this)
        if (FocusEngine.isBlocked(store)) {
            openApp(scan = true)
            return
        }
        FocusEngine.lockManually(this, store, store.activeProfileId)
            .onSuccess { FocusUpdates.refreshAll(this) }
            .onFailure { openApp(scan = false) }
        onStartListening()
    }
}

/** Quick Settings "Use key": opens FocusKey with the NFC reader ready. */
class KeyTileService : TileService() {
    override fun onStartListening() {
        val tile = qsTile ?: return
        tile.state = Tile.STATE_INACTIVE
        tile.label = getString(R.string.use_key)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_nfc)
        tile.updateTile()
    }

    override fun onClick() = openApp(scan = true)
}
