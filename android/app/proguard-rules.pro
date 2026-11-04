# Garmin Connect IQ companion SDK (docs/konzept-garmin.md, Abschnitt 3).
# Garmin Connect schickt IQDevice/IQApp als Parcelable in Broadcasts an
# uns zurück; Android packt sie über den KLASSENNAMEN aus. Benennt R8 sie
# im Release um, stürzt die App beim ersten `status` ab
# (ClassNotFoundException: com.garmin.android.connectiq.IQDevice — gesehen
# am Pixel 7 Pro mit fēnix 5, 0.150.0). Der Simulator-Modus zeigt das nicht.
# Das ganze SDK: auch die AIDL-Schnittstelle zum Dienst von Garmin
# Connect (`com.garmin.android.apps.connectmobile.connectiq`) und die
# Serialisierung (`com.garmin.monkeybrains`) laufen über Namen.
-keep class com.garmin.** { *; }
-keep interface com.garmin.** { *; }
-dontwarn com.garmin.**
