package com.focuskey.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.HourglassBottom
import androidx.compose.material.icons.filled.Nfc
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.focuskey.app.R
import com.focuskey.app.data.Profile
import com.focuskey.app.data.SessionPreset

/** Screens pushed over the tabs. */
sealed interface Route {
    data object Profiles : Route
    data class ProfileEditor(val profile: Profile?) : Route
    data class PresetEditor(val preset: SessionPreset?) : Route
    data class ScheduleDetail(val id: String) : Route
    data object Settings : Route
}

/** Four tabs, as on iOS, with pushed screens, the NFC dialog and messages on top. */
@Composable
fun FocusKeyRoot(viewModel: FocusViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val stack = remember { mutableStateListOf<Route>() }
    val snackbar = remember { SnackbarHostState() }
    val message by viewModel.message.collectAsState()

    LaunchedEffect(message) {
        message?.let {
            viewModel.consumeMessage()
            snackbar.currentSnackbarData?.dismiss()
            snackbar.showSnackbar(it)
        }
    }

    val navigate: (Route) -> Unit = { stack.add(it) }
    val back: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

    val state by viewModel.state.collectAsState()
    if (!state.onboardingDone) {
        OnboardingScreen(viewModel)
        NfcDialog(viewModel)
        return
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (stack.isEmpty()) {
                NavigationBar {
                    NavigationBarItem(
                        selected = tab == 0,
                        onClick = { tab = 0 },
                        icon = { Icon(Icons.Filled.Shield, contentDescription = null) },
                        label = { Text(stringResource(R.string.tab_lock)) },
                    )
                    NavigationBarItem(
                        selected = tab == 1,
                        onClick = { tab = 1 },
                        icon = { Icon(Icons.Filled.Schedule, contentDescription = null) },
                        label = { Text(stringResource(R.string.tab_schedules)) },
                    )
                    NavigationBarItem(
                        selected = tab == 2,
                        onClick = { tab = 2 },
                        icon = { Icon(Icons.Filled.HourglassBottom, contentDescription = null) },
                        label = { Text(stringResource(R.string.tab_limits)) },
                    )
                    NavigationBarItem(
                        selected = tab == 3,
                        onClick = { tab = 3 },
                        icon = { Icon(Icons.Filled.BarChart, contentDescription = null) },
                        label = { Text(stringResource(R.string.tab_stats)) },
                    )
                }
            }
        },
    ) { padding ->
        val modifier = Modifier.padding(padding)
        when (val route = stack.lastOrNull()) {
            null -> when (tab) {
                0 -> LockScreen(viewModel, navigate, modifier)
                1 -> ScheduleScreen(viewModel, navigate, modifier)
                2 -> LimitsScreen(viewModel, modifier)
                else -> StatsScreen(viewModel, modifier)
            }
            else -> {
                BackHandler(onBack = back)
                when (route) {
                    Route.Profiles -> ProfilesScreen(viewModel, navigate, back, modifier)
                    is Route.ProfileEditor -> ProfileEditorScreen(viewModel, route.profile, back, modifier)
                    is Route.PresetEditor -> PresetEditorScreen(viewModel, route.preset, back, modifier)
                    is Route.ScheduleDetail -> ScheduleDetailScreen(viewModel, route.id, back, modifier)
                    Route.Settings -> SettingsScreen(viewModel, back, modifier)
                }
            }
        }
    }

    NfcDialog(viewModel)
}

@Composable
private fun NfcDialog(viewModel: FocusViewModel) {
    val scanning by viewModel.nfcScanning.collectAsState()
    val prompt by viewModel.nfcPrompt.collectAsState()
    val error by viewModel.nfcError.collectAsState()
    if (!scanning) return
    AlertDialog(
        onDismissRequest = viewModel::cancelNfcScan,
        icon = { Icon(Icons.Filled.Nfc, contentDescription = null) },
        title = { Text(stringResource(R.string.nfc_ready)) },
        text = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(prompt ?: stringResource(R.string.nfc_hold), textAlign = TextAlign.Center)
                error?.let {
                    Spacer(Modifier.height(12.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = viewModel::cancelNfcScan) { Text(stringResource(R.string.cancel)) } },
    )
}
