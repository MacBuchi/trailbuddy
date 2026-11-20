// Java statt Kotlin mit Absicht: Seit AGP 9 (`android.builtInKotlin=true`
// in der App) scheitert jedes Plugin, das `kotlin-android` selbst anwendet
// — so flutter_tts 4.2.5 (#525); dieselbe Vorlage wie tb_voice. Java braucht kein Kotlin-Plugin.
group = "de.mcbuchi.trailbuddy.ambient"
version = "1.0"

plugins {
    id("com.android.library")
}

android {
    namespace = "de.mcbuchi.trailbuddy.ambient"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
