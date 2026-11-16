package com.focuskey.app.notify

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import androidx.glance.appwidget.updateAll
import com.focuskey.app.tiles.KeyTileService
import com.focuskey.app.tiles.LockTileService
import com.focuskey.app.widget.FocusWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Keeps everything outside the app in step: countdown notification, widget and Quick Settings tiles. */
object FocusUpdates {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun refreshAll(context: Context) {
        val app = context.applicationContext
        FocusNotifications.refreshLive(app)
        scope.launch { runCatching { FocusWidget().updateAll(app) } }
        runCatching { TileService.requestListeningState(app, ComponentName(app, LockTileService::class.java)) }
        runCatching { TileService.requestListeningState(app, ComponentName(app, KeyTileService::class.java)) }
    }
}
