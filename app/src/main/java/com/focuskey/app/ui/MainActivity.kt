package com.focuskey.app.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.focuskey.app.notify.FocusNotifications
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.focuskey.app.nfc.NfcKeyReader
import com.focuskey.app.ui.theme.FocusKeyTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val viewModel: FocusViewModel by viewModels()
    private lateinit var nfcReader: NfcKeyReader

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        nfcReader = NfcKeyReader(this)
        viewModel.nfcAvailability = { nfcReader.availability }
        FocusNotifications.ensureChannels(this)
        // Countdown and pomodoro alerts need permission from Android 13.
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }

        // NFC reader mode only works while the activity is in the foreground.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                try {
                    viewModel.nfcScanning.collect { scanning ->
                        if (scanning) nfcReader.start(viewModel::onTagRead) else stopNfc()
                    }
                } finally {
                    stopNfc()
                }
            }
        }

        setContent {
            FocusKeyTheme {
                FocusKeyRoot(viewModel)
            }
        }
        handleScanRequest(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleScanRequest(intent)
    }

    /** Opened from the widget or a Quick Settings tile to use the key. */
    private fun handleScanRequest(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_SCAN, false) == true) {
            intent.removeExtra(EXTRA_SCAN)
            viewModel.startNfcScan()
        }
    }

    override fun onResume() {
        super.onResume()
        viewModel.onResume()
    }

    companion object {
        const val EXTRA_SCAN = "scan"
    }

    private fun stopNfc() {
        runCatching { nfcReader.stop() }
    }
}
