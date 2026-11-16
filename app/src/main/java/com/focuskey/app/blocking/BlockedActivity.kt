package com.focuskey.app.blocking

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.FocusStore
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.ui.formatClock
import com.focuskey.app.ui.theme.FocusKeyTheme

/** Full-screen shield shown over blocked apps and websites. */
class BlockedActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = goHome()
        })
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    private fun render() {
        val target = intent.getStringExtra(EXTRA_TARGET).orEmpty()
        val isWebsite = intent.getBooleanExtra(EXTRA_IS_WEBSITE, false)
        val protection = intent.getBooleanExtra(EXTRA_PROTECTION, false)
        val name = if (isWebsite) target else appLabel(target)

        setContent {
            FocusKeyTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Column(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Image(
                            painter = painterResource(R.drawable.logo),
                            contentDescription = null,
                            modifier = Modifier.size(120.dp).clip(RoundedCornerShape(28.dp))
                        )
                        Spacer(Modifier.height(24.dp))
                        Text(
                            getString(R.string.blocked_title),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            when {
                                protection -> getString(R.string.blocked_protection)
                                isWebsite -> getString(R.string.blocked_site, name)
                                else -> getString(R.string.blocked_app, name)
                            },
                            style = MaterialTheme.typography.bodyLarge,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            reason(),
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(32.dp))
                        Button(onClick = ::goHome, modifier = Modifier.fillMaxWidth()) {
                            Text(getString(R.string.back_to_focus))
                        }
                    }
                }
            }
        }
    }

    /** Why it's blocked and until when, picking the most specific source. */
    private fun reason(): String {
        val store = FocusStore(this)
        val now = System.currentTimeMillis()
        val plan = store.activePomodoro(now)
        return when {
            plan != null && store.isLocked -> getString(R.string.reason_pomodoro, formatClock(this, store.sessionEnd))
            store.isLocked && store.sessionEnd > now -> getString(R.string.reason_session, formatClock(this, store.sessionEnd))
            store.isLocked -> getString(R.string.reason_key)
            store.isLimitLocked && !store.isScheduleLocked -> getString(R.string.reason_limit)
            else -> {
                val schedule = FocusEngine.runningSchedules(store, now).firstOrNull()
                if (schedule != null) {
                    val end = FocusEngine.run { schedule.currentIntervalEnd(now.toLocalDateTime()).toEpochMillis() }
                    getString(R.string.reason_schedule, schedule.name.ifEmpty { getString(R.string.schedule_default_name) }, formatClock(this, end))
                } else {
                    getString(R.string.reason_key)
                }
            }
        }
    }

    private fun appLabel(packageName: String): String = try {
        val info = packageManager.getApplicationInfo(packageName, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        getString(R.string.this_app)
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    companion object {
        const val EXTRA_TARGET = "target"
        const val EXTRA_IS_WEBSITE = "isWebsite"
        const val EXTRA_PROTECTION = "protection"
    }
}
