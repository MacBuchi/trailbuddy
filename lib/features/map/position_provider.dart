import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// Die eigene Position auf der Karte (PilzBuddy-Muster, gekürzt). Sie
// bleibt auf dem Gerät: Nichts hier schickt sie irgendwohin, und Trails
// entstehen weiter nur aus importierten Dateien (Phase 1).

/// Live-Position für den Punkt auf der Karte. Liefert null, wenn
/// Standortdienste aus sind oder die Berechtigung (noch) fehlt — es wird
/// hier bewusst NICHT gefragt: Ein Systemdialog beim ersten Start, bevor
/// jemand irgendetwas angetippt hat, wäre genau die Überrumpelung, die
/// Google Play „Prominent Disclosure" nennt. Gefragt wird nur über
/// [positionFixProvider], nach einem Tipp auf „Meine Position"; danach
/// wird dieser Provider invalidiert.
final positionStreamProvider = StreamProvider<Position?>((ref) async* {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield null;
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // erst ab 5 m Bewegung neu zeichnen
      ),
    );
  } catch (_) {
    yield null; // Die Position ist ein Zusatz, nie ein Fehlerfall.
  }
});

/// Ein EINZELNER Fix — und die einzige Stelle der App, die nach der
/// Standortberechtigung fragt. Als Provider, damit Widget-Tests ihn
/// ersetzen: Den Plattform-Kanal gibt es dort nicht.
typedef PositionFix = Future<Position?> Function();

final positionFixProvider = Provider<PositionFix>((ref) => _platformFix);

Future<Position?> _platformFix() async {
  if (kIsWeb) return _webFix();
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}

/// So lange wartet der Fix im Browser höchstens.
const kWebFixTimeout = Duration(seconds: 30);

/// Der Fix im Browser (#400), an zwei Stellen von `geolocator_web` 4.1.4
/// vorbei:
///
/// * `requestPermission` fragt dort selbst einen Fix ab und meldet JEDEN
///   Fehler als `deniedForever` — eine Zeitüberschreitung im Haus hieß
///   „verboten", und danach kam der eigentliche Fix noch einmal. Der
///   Browser fragt ohnehin beim ersten Fix nach; der genügt.
/// * Ohne Zeitlimit wartet das Paket einen Tag, und ein `timeLimit` geht
///   als Mikro- statt Millisekunden hinaus. Ohne Empfänger blieb der
///   Knopf so ohne jede Antwort. Das Limit setzt deshalb Dart selbst.
Future<Position?> _webFix() async {
  try {
    if (await Geolocator.checkPermission() == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: WebSettings(
        accuracy: LocationAccuracy.high,
        // Ein Fix von eben ist gut genug und kommt sofort.
        maximumAge: const Duration(seconds: 30),
      ),
    ).timeout(kWebFixTimeout);
  } catch (_) {
    return null;
  }
}

/// Hat der Browser den Standort für diese Seite gesperrt (#400)? Dann
/// fragt er nie wieder von selbst — freigeben lässt er sich nur über das
/// Symbol in der Adressleiste, und das muss die Meldung sagen. Außerhalb
/// des Browsers immer nein: Dort nennt die Meldung die App-Einstellungen.
typedef LocationBlockedCheck = Future<bool> Function();

final locationBlockedProvider = Provider<LocationBlockedCheck>((ref) => kIsWeb
    ? () async {
        try {
          return await Geolocator.checkPermission() == LocationPermission.deniedForever;
        } catch (_) {
          return false;
        }
      }
    : () async => false);
