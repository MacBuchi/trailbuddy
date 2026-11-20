package de.mcbuchi.trailbuddy

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import okhttp3.Call
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import org.maplibre.android.module.http.HttpRequestUtil
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Zählt, was MapLibre an den Kartenhost schickt (#596 H7) — nur in der
 * Dev-App. Die Dart-Seite zählt ihre eigenen Abrufe selbst
 * (`lib/features/map/host_requests.dart`); Karte und Wege lädt auf
 * Android aber die native Engine über OkHttp, und dorthin sieht Dart
 * nicht. Gezählt wird, was wirklich ans Netz geht: Was MapLibre aus
 * seinem Ambient Cache bedient, kommt hier gar nicht an.
 *
 * Je Pfad eine Zahl, eingeteilt wird in Dart (`hostRequestKindOf`), damit
 * es EINE Regel gibt. Der Kanal heißt in Dart gleich
 * (`android_manifest_test`).
 */
class HostRequestCounter(messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "de.mcbuchi.trailbuddy/host_requests"

        /** Der Kartenhost; alles andere zählt nicht. */
        private const val HOST = "tiles.mcbuchi.de"

        /** Höchstens so viele verschiedene Pfade — Orte-Zellen sind viele
         *  kleine Dateien, Kacheln sind Range-Anfragen auf wenige Archive. */
        private const val MAX_PATHS = 2000

        private val counts = ConcurrentHashMap<String, AtomicInteger>()

        @Volatile
        private var installed = false

        /**
         * Hängt den Zähler vor MapLibres HTTP. Muss laufen, bevor die
         * erste Karte etwas lädt; der Client gleicht MapLibres eigener
         * Vorgabe (`HttpRequestImpl.getDispatcher`: 20 je Host).
         */
        fun install() {
            if (installed) return
            installed = true
            val client = OkHttpClient.Builder()
                .dispatcher(Dispatcher().apply { maxRequestsPerHost = 20 })
                .build()
            HttpRequestUtil.setOkHttpClient(
                Call.Factory { request ->
                    val url = request.url
                    if (url.host == HOST) {
                        val path = url.encodedPath
                        val counter = counts[path]
                            ?: if (counts.size < MAX_PATHS) {
                                counts.computeIfAbsent(path) { AtomicInteger() }
                            } else {
                                counts.computeIfAbsent("…") { AtomicInteger() }
                            }
                        counter.incrementAndGet()
                    }
                    client.newCall(request)
                },
            )
        }
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "counts" -> result.success(counts.mapValues { it.value.get() })
                "reset" -> {
                    counts.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
