package de.mcbuchi.trailbuddy

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Die Route auf die Garmin-Uhr (docs/konzept-garmin.md, Abschnitt 3):
 * Garmins Companion-SDK, das über die Garmin-Connect-App mit der Uhr
 * spricht. TrailBuddy hat kein Garmin-Konto und schickt Garmin nichts —
 * die Nachrichten gehen über Garmin Connect auf dem Telefon an UNSERE
 * Uhr-App (Entscheidung 2). Der Kanalname steht in Dart in
 * `lib/features/garmin/garmin_bridge_io.dart`; ein Test hält beide
 * zusammen.
 *
 * Drei Methoden: `status` (Garmin Connect da? welche Uhr verbunden? unsere
 * App darauf?), `send` (Nachrichten der Reihe nach, jede wartet auf die
 * Bestätigung der vorigen), und von hier nach Dart `message` — die
 * Antwort der Uhr („gespeichert"). Das SDK wird erst beim ersten `status`
 * gestartet, nie beim App-Start: Wer keine Uhr hat, lädt nichts.
 *
 * Kein Test-Netz für Kotlin; die Dart-Seite hat eines (Fake-Brücke).
 */
class GarminBridge(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "de.mcbuchi.trailbuddy/garmin"

        /** Paket der Garmin-Connect-App (`<queries>` im Manifest des SDK). */
        const val GARMIN_CONNECT = "com.garmin.android.apps.connectmobile"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    private var iq: ConnectIQ? = null
    private var ready = false
    private var appId: String? = null
    private val waiting = mutableListOf<() -> Unit>()
    private val listening = mutableSetOf<Long>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val id = call.argument<String>("appId")
                    if (id.isNullOrEmpty()) {
                        result.error("no_app", "appId fehlt", null)
                    } else {
                        status(id, call.argument<Boolean>("tethered") == true, result)
                    }
                }
                "send" -> {
                    @Suppress("UNCHECKED_CAST")
                    val messages = call.argument<List<Any>>("messages") ?: emptyList()
                    send(messages, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        try {
            if (ready) iq?.unregisterAllForEvents()
            iq?.shutdown(context)
        } catch (e: Exception) {
            // Beim Beenden ist ein Fehler hier keiner mehr.
        }
        iq = null
        ready = false
    }

    private fun connectInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(GARMIN_CONNECT, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** Startet das SDK einmal; [then] läuft, sobald es bereit ist (oder gleich). */
    private fun withSdk(tethered: Boolean, then: () -> Unit, failed: (String) -> Unit) {
        if (ready) return then()
        waiting.add(then)
        if (iq != null) return
        val type = if (tethered) ConnectIQ.IQConnectType.TETHERED else ConnectIQ.IQConnectType.WIRELESS
        val sdk = ConnectIQ.getInstance(context, type)
        iq = sdk
        sdk.initialize(context, false, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                ready = true
                val all = waiting.toList()
                waiting.clear()
                all.forEach { it() }
            }

            override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus) {
                iq = null
                waiting.clear()
                failed(status.name)
            }

            override fun onSdkShutDown() {
                ready = false
                iq = null
                listening.clear()
            }
        })
    }

    /**
     * `{connect, device, app}`: Garmin Connect installiert, Name der ersten
     * VERBUNDENEN Uhr (oder null), und ob unsere App darauf liegt
     * (`installed`, `not_installed`, `unknown` — eine per USB geladene
     * Entwickler-App meldet Garmin Connect nicht immer).
     */
    private fun status(id: String, tethered: Boolean, result: MethodChannel.Result) {
        appId = id
        if (!tethered && !connectInstalled()) {
            result.success(mapOf("connect" to false))
            return
        }
        var answered = false
        fun answer(value: Map<String, Any?>) {
            if (answered) return
            answered = true
            main.post { result.success(value) }
        }
        withSdk(tethered, then@{
            val sdk = iq ?: return@then answer(mapOf("connect" to true))
            val device = try {
                sdk.connectedDevices?.firstOrNull()
            } catch (e: Exception) {
                null
            }
            if (device == null) return@then answer(mapOf("connect" to true))
            listen(sdk, device, id)
            try {
                sdk.getApplicationInfo(id, device, object : ConnectIQ.IQApplicationInfoListener {
                    override fun onApplicationInfoReceived(app: IQApp) {
                        answer(mapOf("connect" to true, "device" to device.friendlyName, "app" to "installed"))
                    }

                    override fun onApplicationNotInstalled(applicationId: String) {
                        answer(mapOf("connect" to true, "device" to device.friendlyName, "app" to "not_installed"))
                    }
                })
            } catch (e: Exception) {
                answer(mapOf("connect" to true, "device" to device.friendlyName, "app" to "unknown"))
            }
            // Antwortet Garmin Connect nicht (gesehen bei Entwickler-Apps):
            // nach 3 s „unbekannt", der Schalter steht trotzdem.
            main.postDelayed({
                answer(mapOf("connect" to true, "device" to device.friendlyName, "app" to "unknown"))
            }, 3000)
        }, { error -> answer(mapOf("connect" to true, "error" to error)) })
    }

    /** Die Antworten der Uhr gehen als `message` an Dart. */
    private fun listen(sdk: ConnectIQ, device: IQDevice, id: String) {
        if (!listening.add(device.deviceIdentifier)) return
        try {
            sdk.registerForAppEvents(device, IQApp(id), object : ConnectIQ.IQApplicationEventListener {
                override fun onMessageReceived(
                    device: IQDevice,
                    app: IQApp,
                    message: List<Any>,
                    status: ConnectIQ.IQMessageStatus,
                ) {
                    if (status != ConnectIQ.IQMessageStatus.SUCCESS) return
                    for (m in message) main.post { channel.invokeMethod("message", m) }
                }
            })
        } catch (e: Exception) {
            listening.remove(device.deviceIdentifier)
        }
    }

    /**
     * Der Reihe nach an die erste verbundene Uhr; jede Nachricht wartet auf
     * die Bestätigung der vorigen. Ergebnis: `SUCCESS` oder der Name des
     * ersten Fehlers (`FAILURE_MESSAGE_TOO_LARGE` …), dazu wie viele
     * angekommen sind.
     */
    private fun send(messages: List<Any>, result: MethodChannel.Result) {
        val sdk = iq
        val id = appId
        if (sdk == null || !ready || id == null) {
            result.success(mapOf("status" to "NOT_READY", "sent" to 0))
            return
        }
        val device = try {
            sdk.connectedDevices?.firstOrNull()
        } catch (e: Exception) {
            null
        }
        if (device == null) {
            result.success(mapOf("status" to "FAILURE_DEVICE_NOT_CONNECTED", "sent" to 0))
            return
        }
        val app = IQApp(id)
        fun next(i: Int) {
            if (i >= messages.size) {
                main.post { result.success(mapOf("status" to "SUCCESS", "sent" to i)) }
                return
            }
            try {
                sdk.sendMessage(device, app, messages[i], object : ConnectIQ.IQSendMessageListener {
                    override fun onMessageStatus(device: IQDevice, app: IQApp, status: ConnectIQ.IQMessageStatus) {
                        if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                            next(i + 1)
                        } else {
                            main.post { result.success(mapOf("status" to status.name, "sent" to i)) }
                        }
                    }
                })
            } catch (e: Exception) {
                main.post { result.success(mapOf("status" to "FAILURE_UNKNOWN", "sent" to i)) }
            }
        }
        next(0)
    }
}
