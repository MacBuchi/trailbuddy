package de.mcbuchi.trailbuddy

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream

/**
 * Der einzige native Code im Projekt (Muster PilzBuddy): vier
 * MethodChannels — die geladene Update-APK an den System-Installer geben,
 * lesen, warum die App beim letzten Mal beendet wurde (#40), den
 * Bildschirm in der Navigation anlassen und die Navigation als
 * Bild-im-Bild (beide #232) — und der Benachrichtigungs-Kanal für Push
 * (#34).
 *
 * Beendigungsgründe: Android führt seit Version 11 selbst Buch darüber,
 * und eine App darf ihre EIGENEN Einträge ohne jede Berechtigung lesen.
 * Das schließt die Lücke, die `error_reports` prinzipbedingt hat: Dort
 * landet nur, was die App überlebt — ein ANR oder Absturz hinterlässt
 * nichts. Bewusst zwei Methoden statt einer: Die Übersicht ist billig,
 * der ANR-Thread-Dump ist es nicht (Rohdatei ~1,8 MB). Dart holt ihn nur
 * für Einträge, die es noch nicht gemeldet hat.
 *
 * Jede Zeile hier hat kein Test-Netz; die Dart-Seite
 * (`lib/data/exit_reporting.dart`, `tombstone.dart`) hat eines.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        /** Update der GitHub-APK: fertige Datei an den System-Installer geben.
         *  Der Name steht in Dart in `lib/data/apk_installer.dart`; ein Test
         *  hält beide zusammen. */
        const val INSTALL_CHANNEL = "de.mcbuchi.trailbuddy/apk_install"

        /** Beendigungsgründe; der Name steht in `lib/data/exit_info_repository.dart`. */
        const val EXIT_CHANNEL = "de.mcbuchi.trailbuddy/exit_info"

        /** Bildschirm an in der Folgeansicht (#232); der Name steht in
         *  `lib/core/screen_awake_io.dart`. Das Flag hängt am Fenster und
         *  gilt nur, solange es sichtbar ist — keine Berechtigung. */
        const val SCREEN_CHANNEL = "de.mcbuchi.trailbuddy/screen"

        /** Bild-im-Bild in der Navigation (#232, Konzept-Routing 9.6); der
         *  Name steht in `lib/core/picture_in_picture_io.dart`. */
        const val PIP_CHANNEL = "de.mcbuchi.trailbuddy/pip"

        /** „Beenden" im Fenster: ein Broadcast nur an uns selbst. */
        const val PIP_STOP_ACTION = "de.mcbuchi.trailbuddy.PIP_STOP"

        /** Hochkant, wie man das Telefon am Lenker hält (9.6). */
        val PIP_ASPECT = Rational(3, 4)

        /**
         * Genug für den Haupt-Thread — und zugleich die Grenze der Spalte
         * `stack` (4000 Zeichen; `ErrorReportRepository` schneidet auf
         * dieselbe Zahl, mehr ginge still verloren).
         */
        const val TRACE_CHARS = 4000

        /** Obergrenze beim Lesen, damit ein Riesen-Dump nichts blockiert. */
        const val TRACE_BYTES = 4 * 1024 * 1024
    }

    /**
     * Der Kanal, auf dem FCM Meldungen anzeigt (#34). Sein Name steht im
     * Manifest (`default_notification_channel_id`) und in strings.xml; der
     * Manifest-Test hält alle drei zusammen.
     *
     * IMPORTANCE_HIGH, weil sich die Wichtigkeit nach dem ERSTEN Anlegen
     * nicht mehr ändern lässt — leiser drehen kann der Nutzer selbst,
     * lauter niemand (PilzBuddy #277). Wer die Stufe je ändern will,
     * braucht eine NEUE Kanal-ID. Ohne diese Zeilen legte FCM still einen
     * eigenen, leisen Kanal an: nur ein Symbol in der Statusleiste.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nicht exportiert: Nur die eigene RemoteAction des Fensters ruft ihn.
        ContextCompat.registerReceiver(
            this, pipStopReceiver, IntentFilter(PIP_STOP_ACTION), ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.notification_channel_id),
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.notification_channel_description)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    /**
     * Zurück auf der Karte, wenn nichts mehr offen ist (#175): die App in
     * den Hintergrund legen, NICHT beenden. Ohne diese Zeilen ruft Flutter
     * `finish()` — die Karte startet beim nächsten Öffnen von vorn, und
     * eine laufende Fahrt verliert ihre Anzeige bis zum `restore()`. So
     * verhält sich die App wie der Startbildschirm-Weg von Android selbst.
     * Dart ruft das nur, wenn kein Navigator mehr etwas zu schließen hat
     * (`AppShell` in `router.dart`).
     */
    override fun onDestroy() {
        unregisterReceiver(pipStopReceiver)
        super.onDestroy()
    }

    // ---- Bild-im-Bild (#232, Konzept-Routing 9.6) ----

    private var pipChannel: MethodChannel? = null

    /** Nur bei laufender Navigation; Dart schaltet es mit ihr an und aus. */
    private var pipAllowed = false

    private val pipStopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            pipChannel?.invokeMethod("stop", null)
        }
    }

    /** Ab Android 8 — und nur, wo das Gerät es anbietet (manche Go-Geräte nicht). */
    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /**
     * Ab Android 12 geht es von selbst ins Fenster, sobald man nach Hause
     * wischt (`setAutoEnterEnabled`); darunter über [onUserLeaveHint]. Die
     * eine Aktion ist „Beenden"; ein Tipp aufs Fenster holt die App zurück.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun pipParams(): PictureInPictureParams {
        val stop = RemoteAction(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
            "Beenden",
            "Navigation beenden",
            PendingIntent.getBroadcast(
                this, 0, Intent(PIP_STOP_ACTION).setPackage(packageName), PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return PictureInPictureParams.Builder()
            .setAspectRatio(PIP_ASPECT)
            .setActions(listOf(stop))
            .apply { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setAutoEnterEnabled(pipAllowed) }
            .build()
    }

    private fun allowPip(on: Boolean) {
        pipAllowed = on
        if (!pipSupported()) return
        setPictureInPictureParams(pipParams())
        // Navigation vorbei, während die App klein ist: Das Fenster zeigte
        // nur noch eine Karte ohne Route — zu.
        if (!on && isInPictureInPictureMode) moveTaskToBack(true)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed && pipSupported() && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                enterPictureInPictureMode(pipParams())
            } catch (e: IllegalStateException) {
                // Vom Nutzer für die App abgeschaltet: Dann ist die
                // Benachrichtigung die Anzeige.
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", mapOf("inPip" to isInPictureInPictureMode))
    }

    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "Pfad fehlt", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXIT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exitReasons" ->
                        result.success(exitReasons(call.argument<Int>("limit") ?: 10))
                    "exitTrace" ->
                        result.success(exitTrace(call.argument<Long>("timestamp") ?: 0L))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "allow" -> {
                        allowPip(call.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Ab Android 8 eine Freigabe je App; darunter immer erlaubt (minSdk 24). */
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Systemeinstellung für genau diese App öffnen, nicht die globale Liste. */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /**
     * Über einen FileProvider statt `file://` (ab Android 7 verboten); der
     * Installer läuft in einem fremden Prozess und braucht die Leseerlaubnis.
     * Installiert wird NICHT still: Das System fragt. Deshalb reicht
     * REQUEST_INSTALL_PACKAGES.
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Datei nicht gefunden: $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
            result.success(true)
        } catch (e: Exception) {
            // Dart fällt daraufhin auf den Browser-Download zurück.
            result.error("install_failed", e.message, null)
        }
    }

    // ---- Beendigungsgründe (#40, PilzBuddy #147/#394) ----

    /** Übersicht ohne Thread-Dump — billig genug für jeden App-Start. */
    private fun exitReasons(limit: Int): List<Map<String, Any?>> {
        val infos = historicalExits(limit) ?: return emptyList()
        return infos.map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to info.reason,
                "reasonName" to reasonName(info.reason),
                "description" to info.description,
                "importance" to info.importance,
                // getRss() und getPss() liefern BEREITS kB — hier nichts
                // teilen, `AppExit.summary` rechnet in MB um (PilzBuddy
                // #151: ein zweites / 1024 machte aus 1,9 GB „2 MB").
                "rssKb" to info.rss,
                "pssKb" to info.pss,
                "hasTrace" to hasTrace(info),
            )
        }
    }

    /**
     * Hat Android zu diesem Eintrag etwas hinterlegt? ANR: ein Text-Dump.
     * Nativer Absturz: ab API 31 ein Tombstone als Protobuf.
     */
    private fun hasTrace(info: ApplicationExitInfo): Boolean = when (info.reason) {
        ApplicationExitInfo.REASON_ANR -> true
        ApplicationExitInfo.REASON_CRASH_NATIVE ->
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        else -> false
    }

    /**
     * Der Dump zu einem Eintrag: beim ANR der Haupt-Thread-Abschnitt als
     * Text, beim nativen Absturz das rohe Tombstone.
     *
     * **Das Tombstone wird hier NICHT gelesen, nur durchgereicht.** Es ist
     * ein Protobuf, und das Auseinandernehmen gehört auf die Dart-Seite
     * (`lib/data/tombstone.dart`): Diese Datei hat keinen Test, drüben ist
     * der Leser mit erfundenen Tombstones prüfbar.
     */
    private fun exitTrace(timestamp: Long): Any? {
        val info = historicalExits(20)?.firstOrNull { it.timestamp == timestamp }
            ?: return null
        if (!hasTrace(info)) return null
        return try {
            info.traceInputStream?.use { stream ->
                if (info.reason == ApplicationExitInfo.REASON_ANR) {
                    mainThreadSection(readTrace(stream))
                } else {
                    // Als ByteArray über den Kanal — Dart bekommt eine Uint8List.
                    readRaw(stream)
                }
            }
        } catch (e: Exception) {
            // Der Dump ist ein Extra; der Eintrag selbst ist die halbe Antwort.
            null
        }
    }

    private fun readRaw(stream: InputStream): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(64 * 1024)
        var total = 0
        while (total < TRACE_BYTES) {
            val read = stream.read(chunk)
            if (read <= 0) break
            buffer.write(chunk, 0, read)
            total += read
        }
        return buffer.toByteArray()
    }

    private fun historicalExits(limit: Int): List<ApplicationExitInfo>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(packageName, 0, limit)
        } catch (e: Exception) {
            null
        }
    }

    /** Android liefert den ANR-Dump gzip-gepackt; erkannt an der Signatur. */
    private fun readTrace(stream: InputStream): String {
        val raw = readRaw(stream)
        val gzipped = raw.size > 1 &&
            raw[0] == 0x1f.toByte() && raw[1] == 0x8b.toByte()
        return if (gzipped) {
            GZIPInputStream(raw.inputStream()).use { it.readBytes().decodeToString() }
        } else {
            raw.decodeToString()
        }
    }

    /** Nur der Haupt-Thread: Alle Threads passen weder in die Spalte noch in einen Digest. */
    private fun mainThreadSection(dump: String): String {
        val start = dump.indexOf("\"main\"")
        if (start < 0) return dump.take(TRACE_CHARS)
        val end = dump.indexOf("\n\n", start)
        val section = if (end > start) dump.substring(start, end) else dump.substring(start)
        return section.take(TRACE_CHARS)
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "UNKNOWN_$reason"
    }
}
