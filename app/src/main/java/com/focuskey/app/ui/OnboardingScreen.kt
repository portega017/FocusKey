package com.focuskey.app.ui

import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Nfc
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.nfc.NfcKeyReader

/** First-launch walkthrough: permission, first profile, NFC key, quick sessions and strict mode. */
@Composable
fun OnboardingScreen(viewModel: FocusViewModel) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var page by remember { mutableIntStateOf(0) }
    var picking by remember { mutableStateOf(false) }
    var strict by remember { mutableStateOf(false) }
    val last = 5

    if (picking) {
        BackHandler { picking = false }
        AppPickerScreen(
            initial = state.activeProfile?.selection ?: com.focuskey.app.data.Selection(),
            onDone = { viewModel.setActiveProfileSelection(it); picking = false },
            onCancel = { picking = false },
        )
        return
    }
    BackHandler(enabled = page > 0) { page-- }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp)) {
            Column(
                Modifier.weight(1f).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
            ) {
                when (page) {
                    0 -> Page(Icons.Filled.Shield, R.string.onb_welcome_title, R.string.onb_welcome_text)
                    1 -> Page(Icons.Filled.Security, R.string.onb_permission_title, R.string.onb_permission_text) {
                        if (state.isAuthorized) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = com.focuskey.app.ui.theme.FocusColors.Green)
                                Spacer(Modifier.size(6.dp))
                                Text(stringResource(R.string.onb_granted), fontWeight = FontWeight.SemiBold)
                            }
                        } else {
                            OutlinedButton(onClick = {
                                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }) { Text(stringResource(R.string.open_settings)) }
                        }
                    }
                    2 -> Page(Icons.Filled.Apps, R.string.onb_apps_title, R.string.onb_apps_text) {
                        OutlinedButton(onClick = { picking = true }) { Text(stringResource(R.string.choose_apps)) }
                        Text(selectionSummary(context, state.activeProfile), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    3 -> Page(Icons.Filled.Nfc, R.string.onb_key_title, R.string.onb_key_text) {
                        Text(
                            NfcKeyReader.KEY_TEXT,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.background(MaterialTheme.colorScheme.surface, CircleShape).padding(horizontal = 16.dp, vertical = 10.dp),
                        )
                    }
                    4 -> Page(Icons.Filled.Bolt, R.string.onb_sessions_title, R.string.onb_sessions_text)
                    else -> Page(Icons.Filled.Key, R.string.strict_mode, R.string.onb_strict_text) {
                        Row(
                            Modifier.background(MaterialTheme.colorScheme.surface, CircleShape).padding(horizontal = 18.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(stringResource(R.string.onb_strict_toggle), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(end = 12.dp))
                            Switch(checked = strict, onCheckedChange = { strict = it })
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                (0..last).forEach {
                    Box(
                        Modifier.padding(4.dp).size(8.dp).background(
                            if (it == page) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f),
                            CircleShape,
                        )
                    )
                }
            }
            Spacer(Modifier.size(12.dp))
            Button(
                onClick = { if (page < last) page++ else viewModel.finishOnboarding(strict) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(if (page < last) R.string.onb_continue else R.string.start)) }
            if (page < last) {
                TextButton(onClick = { viewModel.finishOnboarding(false) }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.onb_skip))
                }
            }
        }
    }
}

@Composable
private fun Page(icon: ImageVector, title: Int, text: Int, accessory: @Composable () -> Unit = {}) {
    Box(
        Modifier.size(112.dp).background(MaterialTheme.colorScheme.primary, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(52.dp))
    }
    Text(stringResource(title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    Text(stringResource(text), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    accessory()
}
