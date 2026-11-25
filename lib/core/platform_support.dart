import 'package:flutter/foundation.dart';

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
