package com.focuskey.app.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.focuskey.app.R
import com.focuskey.app.data.FocusStore
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.notify.FocusNotifications
import com.focuskey.app.notify.FocusUpdates
import com.focuskey.app.ui.MainActivity
import com.focuskey.app.ui.UiState
import com.focuskey.app.ui.presetDuration
import com.focuskey.app.ui.presetName
import com.focuskey.app.ui.profileColor
import com.focuskey.app.ui.statusText

/** Home screen widget: state, and buttons to lock, start a quick session or use the key. */
class FocusWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = UiState.read(context, FocusStore(context))
        provideContent { GlanceTheme { Content(context, state) } }
    }

    @androidx.compose.runtime.Composable
    private fun Content(context: Context, state: UiState) {
        val profile = state.blockingProfile ?: state.activeProfile
        val tint = profileColor(profile?.colorName ?: "indigo")
        val (headline, detail) = statusText(context, state)
        Column(
            GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(20.dp)
                .padding(12.dp)
                .clickable(actionStartActivity<MainActivity>()),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    GlanceModifier.size(30.dp).background(ColorProvider(tint)).cornerRadius(8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        ImageProvider(R.drawable.ic_notification),
                        contentDescription = null,
                        modifier = GlanceModifier.size(18.dp),
                        colorFilter = ColorFilter.tint(ColorProvider(Color.White)),
                    )
                }
                Spacer(GlanceModifier.width(8.dp))
                Column {
                    Text(headline, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = GlanceTheme.colors.onSurface), maxLines = 1)
                    Text(detail ?: profile?.name.orEmpty(), style = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant), maxLines = 1)
                }
            }
            Spacer(GlanceModifier.height(10.dp))
            when {
                state.canUnlockWithKey -> WidgetButton(context.getString(R.string.use_key), tint, actionStartActivity<MainActivity>(
                    actionParametersOf(ActionParameters.Key<Boolean>(MainActivity.EXTRA_SCAN) to true)))
                state.isLocked || state.pomodoro != null || !state.isAuthorized -> Unit
                state.presets.isNotEmpty() -> Row(GlanceModifier.fillMaxWidth()) {
                    state.presets.take(2).forEachIndexed { index, preset ->
                        if (index > 0) Spacer(GlanceModifier.width(6.dp))
                        val presetProfile = state.profile(preset.profileId)
                        WidgetButton(
                            "${presetName(preset, presetProfile)} · ${presetDuration(context, preset)}",
                            profileColor(presetProfile?.colorName ?: "indigo"),
                            actionRunCallback<StartPresetAction>(actionParametersOf(StartPresetAction.PRESET to preset.id)),
                            GlanceModifier.defaultWeight(),
                        )
                    }
                }
                else -> WidgetButton(context.getString(R.string.lock), tint, actionRunCallback<LockAction>())
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun WidgetButton(text: String, color: Color, action: androidx.glance.action.Action, modifier: GlanceModifier = GlanceModifier.fillMaxWidth()) {
        Box(
            modifier.height(36.dp).background(ColorProvider(color)).cornerRadius(18.dp).clickable(action),
            contentAlignment = Alignment.Center,
        ) {
            Text(text, style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Medium, fontSize = 13.sp), maxLines = 1)
        }
    }
}

class FocusWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = FocusWidget()
}

/** Locks the selected profile from the widget. */
class LockAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val store = FocusStore(context)
        FocusEngine.lockManually(context, store, store.activeProfileId)
        FocusUpdates.refreshAll(context)
    }
}

/** Starts a quick session (timed or pomodoro) from the widget. */
class StartPresetAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val store = FocusStore(context)
        val preset = store.presets.firstOrNull { it.id == parameters[PRESET] } ?: return
        val pomodoro = preset.pomodoro
        if (pomodoro != null) {
            FocusEngine.startPomodoro(context, store, preset.profileId, pomodoro.focusMinutes, pomodoro.breakMinutes, pomodoro.cycles)
                .onSuccess { FocusNotifications.schedulePomodoro(context, it) }
        } else {
            FocusEngine.lockManually(context, store, preset.profileId, preset.minutes)
        }
        FocusUpdates.refreshAll(context)
    }

    companion object {
        val PRESET = ActionParameters.Key<String>("preset")
    }
}
