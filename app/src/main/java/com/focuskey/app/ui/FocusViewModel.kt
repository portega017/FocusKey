package com.focuskey.app.ui

import android.app.Application
import android.content.SharedPreferences
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.focuskey.app.data.FocusStore
import com.focuskey.app.data.Schedule
import com.focuskey.app.data.Selection
import com.focuskey.app.logic.FocusEngine
import com.focuskey.app.nfc.NfcKeyReader
import java.time.LocalDateTime
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Android equivalent of FocusModel on iOS. */
class FocusViewModel(application: Application) : AndroidViewModel(application) {

    private val store = FocusStore(application)

    private val _selection = MutableStateFlow(store.selection)
    val selection: StateFlow<Selection> = _selection.asStateFlow()

    /** Manual lock (button / NFC). */
    private val _isLocked = MutableStateFlow(store.isLocked)
    val isLocked: StateFlow<Boolean> = _isLocked.asStateFlow()

    private val _schedules = MutableStateFlow(store.schedules)
    val schedules: StateFlow<List<Schedule>> = _schedules.asStateFlow()

    private val _scheduleSkips = MutableStateFlow(store.scheduleSkips)

    private val _status = MutableStateFlow("Autoriza el bloqueo para empezar.")
    val status: StateFlow<String> = _status.asStateFlow()

    private val _isAuthorized = MutableStateFlow(FocusEngine.isAuthorized(application))
    val isAuthorized: StateFlow<Boolean> = _isAuthorized.asStateFlow()

    /** Re-evaluated every 30 s so the UI follows schedules starting or ending. */
    private val _now = MutableStateFlow(LocalDateTime.now())
    val now: StateFlow<LocalDateTime> = _now.asStateFlow()

    /** One-off messages shown as a snackbar on the schedules tab. */
    private val _scheduleMessage = MutableStateFlow<String?>(null)
    val scheduleMessage: StateFlow<String?> = _scheduleMessage.asStateFlow()

    // NFC scan sheet
    private val _nfcScanning = MutableStateFlow(false)
    val nfcScanning: StateFlow<Boolean> = _nfcScanning.asStateFlow()
    private val _nfcMessage = MutableStateFlow<String?>(null)
    val nfcMessage: StateFlow<String?> = _nfcMessage.asStateFlow()

    /** The blocking service and the UI share the same preferences: reload on any change. */
    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> reloadFromStore() }

    init {
        store.prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        viewModelScope.launch {
            while (true) {
                tick()
                delay(30_000)
            }
        }
    }

    override fun onCleared() {
        store.prefs.unregisterOnSharedPreferenceChangeListener(prefsListener)
    }

    private var lastAuthorized: Boolean? = null

    /** Called when the app comes to the foreground (scenePhase == .active on iOS). */
    fun refresh() {
        val authorized = FocusEngine.isAuthorized(getApplication())
        if (authorized != lastAuthorized) {
            _status.value = if (authorized) {
                "El servicio de bloqueo está activado."
            } else {
                "Activa el servicio de bloqueo de FocusKey para empezar."
            }
            lastAuthorized = authorized
        }
        _isAuthorized.value = authorized
        tick()
    }

    private fun tick() {
        _now.value = LocalDateTime.now()
        FocusEngine.syncScheduleLock(store)
        reloadFromStore()
    }

    private fun reloadFromStore() {
        _selection.value = store.selection
        _isLocked.value = store.isLocked
        _schedules.value = store.schedules
        _scheduleSkips.value = store.scheduleSkips
    }

    // MARK: Locking

    fun updateSelection(selection: Selection) {
        store.selection = selection
        _selection.value = selection
    }

    fun lock() {
        _status.value = FocusEngine.setManualLock(getApplication(), store, true)
        reloadFromStore()
    }

    /** True while a schedule is running now and hasn't been skipped with the tag. */
    fun isScheduleBlocking(now: LocalDateTime): Boolean =
        _schedules.value.any { it.isActive(now) && !FocusEngine.isScheduleSkipped(_scheduleSkips.value, it, now) }

    fun startNfcScan(availability: NfcKeyReader.Availability) {
        when (availability) {
            NfcKeyReader.Availability.UNSUPPORTED ->
                _status.value = "Este dispositivo no tiene NFC."
            NfcKeyReader.Availability.DISABLED ->
                _status.value = "Activa NFC en los ajustes del teléfono para usar tu llave."
            NfcKeyReader.Availability.AVAILABLE -> {
                _nfcMessage.value = null
                _nfcScanning.value = true
            }
        }
    }

    fun cancelNfcScan() {
        _nfcScanning.value = false
    }

    fun onTagRead(isValidKey: Boolean) {
        if (!_nfcScanning.value) return
        if (isValidKey) {
            _nfcScanning.value = false
            _status.value = FocusEngine.handleNfc(getApplication(), store)
            reloadFromStore()
        } else {
            _nfcMessage.value = "La etiqueta no es una llave FocusKey válida."
        }
    }

    // MARK: Schedules

    fun isScheduleActive(schedule: Schedule, now: LocalDateTime = LocalDateTime.now()) =
        schedule.isActive(now)

    fun addSchedule(schedule: Schedule) {
        saveSchedules(_schedules.value + schedule)
    }

    fun updateSchedule(schedule: Schedule) {
        val existing = _schedules.value.firstOrNull { it.id == schedule.id } ?: return
        // A running schedule can't be changed at all.
        if (existing != schedule && existing.isActive()) {
            showScheduleMessage("No puedes modificar un horario mientras está en curso.")
            return
        }
        saveSchedules(_schedules.value.map { if (it.id == schedule.id) schedule else it })
    }

    fun setScheduleEnabled(id: String, enabled: Boolean) {
        val existing = _schedules.value.firstOrNull { it.id == id } ?: return
        if (existing.isActive()) {
            showScheduleMessage("No puedes desactivar un horario mientras está en curso.")
            return
        }
        updateSchedule(existing.copy(isEnabled = enabled))
    }

    fun deleteSchedule(id: String) {
        val schedule = _schedules.value.firstOrNull { it.id == id } ?: return
        if (schedule.isActive()) {
            showScheduleMessage("No puedes eliminar un horario mientras el bloqueo está activo.")
            return
        }
        saveSchedules(_schedules.value.filterNot { it.id == id })
    }

    fun duplicateSchedule(id: String) {
        val schedule = _schedules.value.firstOrNull { it.id == id } ?: return
        addSchedule(
            schedule.copy(
                id = java.util.UUID.randomUUID().toString(),
                name = if (schedule.name.isEmpty()) "" else "${schedule.name} (copia)"
            )
        )
    }

    fun consumeScheduleMessage() {
        _scheduleMessage.value = null
    }

    private fun showScheduleMessage(message: String) {
        _status.value = message
        _scheduleMessage.value = message
    }

    private fun saveSchedules(schedules: List<Schedule>) {
        store.schedules = schedules
        _schedules.value = schedules
        // Like DeviceActivity on iOS: a schedule saved inside its interval starts blocking right away.
        tick()
    }
}
