// Java statt Kotlin mit Absicht: Seit AGP 9 (`android.builtInKotlin=true`
// in der App) scheitert jedes Plugin, das `kotlin-android` selbst anwendet
// — so flutter_tts 4.2.5 (#525). Java braucht kein Kotlin-Plugin.
group = "de.mcbuchi.trailbuddy.voice"
version = "1.0"

plugins {
    id("com.android.library")
}

android {
    namespace = "de.mcbuchi.trailbuddy.voice"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
