package com.focuskey.app.ui

import android.os.Bundle
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
                FocusKeyRoot(
                    viewModel = viewModel,
                    nfcAvailability = { nfcReader.availability }
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        viewModel.refresh()
    }

    private fun stopNfc() {
        runCatching { nfcReader.stop() }
    }
}
