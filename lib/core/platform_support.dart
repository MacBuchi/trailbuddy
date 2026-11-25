import 'package:flutter/foundation.dart';

import 'platform_host_stub.dart'
    if (dart.library.io) 'platform_host_io.dart';

/// Läuft die App als Android-App?
///
/// Bis #644 hieß „nicht im Browser" überall „Android" (`!kIsWeb`). Auf
/// dem iPhone wäre das eine Zusage ohne Beweis: Die Aufzeichnung hängt
/// an einem Android-Vordergrunddienst, Push trägt sich als `android` ein,
/// `geo:` kennt iOS nicht. Was dort noch nicht am Gerät gezeigt ist,
/// fragt deshalb HIER und bleibt auf iOS aus.
///
/// Liest [defaultTargetPlatform], damit ein Test mit
/// `debugDefaultTargetPlatformOverride` beide Plattformen sieht.
bool get isAndroidApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Läuft die App als iOS-App (#644)?
bool get isIosApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Hat dieser PROZESS die nativen Kanäle von Android (#644)?
///
/// Nicht dasselbe wie [isAndroidApp]: `flutter test` spielt Android
/// ([defaultTargetPlatform]), hat aber keine Kanäle der App (Bildschirm,
/// Bild-im-Bild, Garmin, App-Links). Wer einen solchen Kanal anspricht,
/// fragt HIER, damit ein Widget-Test nicht an einem fehlenden Plugin
/// hängt. Die Plattform-Weichen der App stehen alle in dieser Datei;
/// `test/ios_support_test.dart` sucht in `lib/` nach weiteren.
bool get hasAndroidChannels => processIsAndroid;

/// Dasselbe für iOS.
bool get hasIosChannels => processIsIos;
