import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push (#34): Das Google-Services-Plugin liest google-services.json und
// bricht den Build ab, wenn die Datei fehlt. Sie kommt aus der
// Firebase-Konsole des Betreibers (Projekt für de.mcbuchi.trailbuddy) und
// ist öffentlich (nur Kennungen, keine Geheimnisse) — bis sie im Repo
// liegt, baut die App OHNE Firebase, und der Schalter im Profil sagt das.
// Ein Build, der an einer noch nicht angelegten Konsole scheitert, wäre
// ein roter CI-Lauf für alle anderen Änderungen.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release-Signing aus android/key.properties (lokal bzw. von CI aus den
// Secrets ANDROID_KEYSTORE_* erzeugt); ohne die Datei fällt der Build auf
// Debug-Signing zurück. Muster aus PilzBuddy.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

/// Flutters Plattformnamen auf Android-ABIs (Spiegel von
/// `FlutterPluginConstants.PLATFORM_ARCH_MAP`, das Objekt ist intern).
val platformToAbi =
    mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )

android {
    namespace = "de.mcbuchi.trailbuddy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (#116) verlangt Desugaring, auch
        // wenn nichts geplant wird — ohne bricht schon der Build ab.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Umgedrehte Domain des Betreibers, ohne Klarnamen — wie bei
        // PilzBuddy seit 1.88.0. Ab dem ersten AAB-Upload unveränderlich.
        applicationId = "de.mcbuchi.trailbuddy"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // `--target-platform android-arm64` beschränkt nur Flutters eigene
        // Artefakte; die nativen Teile der Plugins kämen weiter für alle
        // ABIs mit (in PilzBuddy 1.42.0: 22 MB von 67). Der Filter leitet
        // sich aus derselben Eigenschaft ab, die Flutter an Gradle
        // durchreicht — das AAB ohne `--target-platform` bleibt vollständig.
        (project.findProperty("target-platform") as String?)
            ?.split(",")
            ?.mapNotNull { platformToAbi[it.trim()] }
            ?.takeIf { it.isNotEmpty() }
            ?.let { ndk.abiFilters.addAll(it) }
    }

    // Zwei Vertriebswege, EINE App (gleiche applicationId, bewusst kein
    // applicationIdSuffix): `github` behält REQUEST_INSTALL_PACKAGES für
    // den In-App-Update-Weg, `play` nimmt die Berechtigung in
    // src/play/AndroidManifest.xml wieder heraus. Ab hier verlangt jeder
    // Build ein `--flavor`, und der Ausgabepfad trägt den Namen.
    flavorDimensions += "distribution"
    productFlavors {
        create("github") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// MapLibre Native AUSDRÜCKLICH auf 13.5.3 (#155), am Plugin vorbei:
// maplibre_android 0.3.5 verlangt `13.0.+` (aufgelöst zu 13.0.3-pre0),
// und erst 13.3.0 legt PMTiles-Bereiche in den Ambient Cache
// (maplibre-native #4290, Schlüssel je Byte-Bereich) — ohne das kein
// „Gesehenes bleibt liegen". 0.3.6 brächte 13.5, bricht aber den Build
// (pubspec.yaml). Geprüft am 2026-10-08: Alle 1603 MapLibre-Methoden,
// die die jnigen-Bindungen von 0.3.5 in 13.0 auflösen, gibt es in 13.5.3
// mit derselben Signatur. Mit maplibre 0.3.6+ fällt die Zeile weg.
configurations.all {
    resolutionStrategy.force("org.maplibre.gl:android-sdk-opengl:13.5.3")
}

dependencies {
    // Für isCoreLibraryDesugaringEnabled (flutter_local_notifications, #116).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
