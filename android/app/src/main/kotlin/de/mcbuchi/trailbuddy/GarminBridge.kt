package de.mcbuchi.trailbuddy

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

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
 * App darauf?), `open` (die Uhr-App öffnen, sonst fragt die Uhr
 * „TrailBuddy öffnen?"), `send` (Nachrichten der Reihe nach, jede wartet
 * auf die Bestätigung der vorigen). Von hier nach Dart: `message` — was
 * die Uhr schickt („hallo", „gespeichert") — und `device` mit dem Stand
 * der Verbindung (`CONNECTED` …), von Garmin Connect gemeldet, nicht
 * abgefragt. Das SDK wird erst beim ersten `status` gestartet, nie beim
 * App-Start: Wer keine Uhr hat, lädt nichts.
 *
 * Kein Test-Netz für Kotlin; die Dart-Seite hat eines (Fake-Brücke).
 */
class GarminBridge(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "de.mcbuchi.trailbuddy/garmin"

        /** Paket der Garmin-Connect-App (`<queries>` im Manifest des SDK). */
        const val GARMIN_CONNECT = "com.garmin.android.apps.connectmobile"

        /**
         * So lange wartet ein Stück auf die Bestätigung. Ohne Grenze hinge
         * das Senden für immer, wenn die Uhr-App nicht antwortet (gesehen im
         * Simulator) — das Handy zeigte dann weder Erfolg noch Fehler.
         */
        const val ACK_TIMEOUT_MS = 20_000L

        /** So lange wartet `open` auf Garmin Connect, dann `TIMEOUT`. */
        const val OPEN_TIMEOUT_MS = 10_000L
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    /**
     * Gesendet wird hier, nie auf dem UI-Thread: Im Simulator-Modus
     * (`GARMIN_TETHERED`) schläft `sendMessage` erst „Simulating BLE" (2–3 s)
     * und schreibt dann auf einen Socket — auf dem UI-Thread wirft Android
     * `NetworkOnMainThreadException` (gesehen am Pixel), und die Karte stünde.
     */
    private val io = Executors.newSingleThreadExecutor()

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
                "open" -> open(result)
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
        io.shutdownNow()
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

    /**
     * Die Antworten der Uhr gehen als `message` an Dart, der Stand der
     * Verbindung als `device`: Verbindet die Uhr neu, fragt Dart, welche
     * Route sie hat (`q`) — statt im Takt nachzusehen.
     */
    private fun listen(sdk: ConnectIQ, device: IQDevice, id: String) {
        if (!listening.add(device.deviceIdentifier)) return
        try {
            sdk.registerForDeviceEvents(device, object : ConnectIQ.IQDeviceEventListener {
                override fun onDeviceStatusChanged(device: IQDevice, status: IQDevice.IQDeviceStatus) {
                    main.post { channel.invokeMethod("device", status.name) }
                }
            })
        } catch (e: Exception) {
            Log.w("TB-GARMIN", "registerForDeviceEvents", e)
        }
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
     * Die Uhr-App auf der ersten verbundenen Uhr öffnen. Läuft sie nicht,
     * fragt die Uhr „TrailBuddy öffnen?"; nach dem Ja meldet sich die App
     * selbst (`hi`). Ergebnis: der Name aus `IQOpenApplicationStatus`
     * (`APP_IS_ALREADY_RUNNING`, `PROMPT_SHOWN_ON_DEVICE`,
     * `APP_IS_NOT_INSTALLED` …), `NOT_READY`, `FAILURE_DEVICE_NOT_CONNECTED`
     * oder nach [OPEN_TIMEOUT_MS] `TIMEOUT`. Auf dem eigenen Thread wie
     * `send` (Simulator-Modus: Socket).
     */
    private fun open(result: MethodChannel.Result) {
        val sdk = iq
        val id = appId
        if (sdk == null || !ready || id == null) {
            result.success("NOT_READY")
            return
        }
        var answered = false
        fun answer(status: String) {
            main.post {
                if (answered) return@post
                answered = true
                Log.i("TB-GARMIN", "open $status")
                result.success(status)
            }
        }
        main.postDelayed({ answer("TIMEOUT") }, OPEN_TIMEOUT_MS)
        io.execute {
            try {
                val device = sdk.connectedDevices?.firstOrNull()
                if (device == null) {
                    answer("FAILURE_DEVICE_NOT_CONNECTED")
                    return@execute
                }
                sdk.openApplication(device, IQApp(id), object : ConnectIQ.IQOpenApplicationListener {
                    override fun onOpenApplicationResponse(
                        device: IQDevice,
                        app: IQApp,
                        status: ConnectIQ.IQOpenApplicationStatus,
                    ) {
                        answer(status.name)
                    }
                })
            } catch (e: Exception) {
                Log.w("TB-GARMIN", "openApplication", e)
                answer("UNKNOWN_FAILURE")
            }
        }
    }

    /**
     * Der Reihe nach an die erste verbundene Uhr; jede Nachricht wartet auf
     * die Bestätigung der vorigen, höchstens [ACK_TIMEOUT_MS]. Ergebnis:
     * `SUCCESS` oder der Name des ersten Fehlers
     * (`FAILURE_MESSAGE_TOO_LARGE`, `FAILURE_TIMEOUT` …), dazu wie viele
     * angekommen sind.
     */
    private fun send(messages: List<Any>, result: MethodChannel.Result) {
        val sdk = iq
        val id = appId
        if (sdk == null || !ready || id == null) {
            Log.i("TB-GARMIN", "send NOT_READY")
            result.success(mapOf("status" to "NOT_READY", "sent" to 0))
            return
        }
        val device = try {
            sdk.connectedDevices?.firstOrNull()
        } catch (e: Exception) {
            null
        }
        if (device == null) {
            Log.i("TB-GARMIN", "send FAILURE_DEVICE_NOT_CONNECTED")
            result.success(mapOf("status" to "FAILURE_DEVICE_NOT_CONNECTED", "sent" to 0))
            return
        }
        val app = IQApp(id)
        var finished = false
        var pending: Runnable? = null
        fun finish(status: String, sent: Int) {
            main.post {
                if (finished) return@post
                finished = true
                Log.i("TB-GARMIN", "send $status after $sent of ${messages.size}")
                pending?.let { main.removeCallbacks(it) }
                result.success(mapOf("status" to status, "sent" to sent))
            }
        }
        fun next(i: Int) {
            if (i >= messages.size) return finish("SUCCESS", i)
            // Bleibt die Bestätigung aus: `FAILURE_TIMEOUT`, das Handy zeigt
            // den Fehler; eine späte Bestätigung danach zählt nicht mehr.
            val timeout = Runnable { finish("FAILURE_TIMEOUT", i) }
            main.post {
                pending?.let { main.removeCallbacks(it) }
                pending = timeout
                main.postDelayed(timeout, ACK_TIMEOUT_MS)
            }
            io.execute {
                try {
                    sdk.sendMessage(device, app, messages[i], object : ConnectIQ.IQSendMessageListener {
                        override fun onMessageStatus(device: IQDevice, app: IQApp, status: ConnectIQ.IQMessageStatus) {
                            main.post {
                                if (finished || pending !== timeout) return@post
                                if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                                    next(i + 1)
                                } else {
                                    finish(status.name, i)
                                }
                            }
                        }
                    })
                } catch (e: Exception) {
                    Log.w("TB-GARMIN", "sendMessage", e)
                    finish("FAILURE_UNKNOWN", i)
                }
            }
        }
        next(0)
    }
}
