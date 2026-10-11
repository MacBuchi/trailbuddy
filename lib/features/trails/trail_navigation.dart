// Übergibt den Trailkopf an die Navi-App des Nutzers (#151; Vorlage
// PilzBuddy #367, `spot_navigation.dart`).
//
// Der Weg ist ein `geo:`-URI, kein Kartendienst im Browser. Das ist die
// einzige Fassung, die am Parkplatz ohne Empfang trägt: Sie öffnet den
// App-Wähler mit dem, was wirklich installiert ist — OsmAnd, Organic
// Maps, Komoot, Google Maps — und **die App baut dabei selbst keine
// Verbindung auf**. Ein fester Kartendienst als Rückfall wäre ein neues
// Netzziel (Datenschutzerklärung) und ein fester Empfänger statt der
// freien Wahl; Konzept 9 schließt ihn aus. Der Rückfall ist die
// Zwischenablage, auch im Browser.
//
// **Wer den Ort bekommt, entscheidet der Nutzer im App-Wähler.** Deshalb
// kein Bestätigungsdialog davor: Der Wähler IST die Bestätigung und nennt
// die Ziel-App beim Namen. Die Übergabe ist nutzerinitiiert — für Data
// Safety keine Weitergabe.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../models/trail.dart';

/// Das URI-Schema, mit dem Android nach einer Karten-App fragt.
///
/// Dieselbe Zeichenkette steht im `<queries>`-Block des Manifests — ohne
/// sie sieht die App ab Android 11 keinen Empfänger, der Wähler bliebe
/// leer, und der Knopf fiele stumm auf die Zwischenablage zurück.
/// `test/android_manifest_test.dart` hält beide Seiten zusammen.
const kGeoScheme = 'geo';

/// Nachkommastellen der übergebenen Koordinate: sechs sind ~11 cm, weit
/// unter allem, was ein GPS im Wald kann; `double.toString()` liefert bis
/// zu 17 und macht die Zwischenablage unlesbar.
const kCoordinateDigits = 6;

/// Wie lang die Beschriftung höchstens wird — sie ist der Pin-Titel in
/// der Ziel-App, kein Freitextfeld.
const kMaxLabelLength = 60;

/// Lesbare Koordinate für Zwischenablage und Meldung: Breite, Komma,
/// Länge, je sechs Nachkommastellen.
/// `toStringAsFixed` schreibt unabhängig von der Sprache einen Punkt —
/// mit Komma wäre die Zeile für Karten-Apps unbrauchbar.
String formatCoordinates(double lat, double lng) =>
    '${lat.toStringAsFixed(kCoordinateDigits)}, '
    '${lng.toStringAsFixed(kCoordinateDigits)}';

/// Der `geo:`-URI zu einem Ort, wahlweise mit Beschriftung.
///
/// Die Koordinate steht **zweimal** darin, und das ist Absicht: Apps, die
/// `q` auswerten, setzen darüber ihren Pin samt Titel; Apps, die es
/// ignorieren, zentrieren auf den Pfad. Die verbreitete Kurzform
/// `geo:0,0?q=…` schickt die zweite Gruppe in den Golf von Guinea.
Uri geoUriFor({required double lat, required double lng, String? label}) {
  final point = '${lat.toStringAsFixed(kCoordinateDigits)},'
      '${lng.toStringAsFixed(kCoordinateDigits)}';
  final title = _sanitizeLabel(label);
  final query = title == null ? point : '$point($title)';
  return Uri.parse('$kGeoScheme:$point?q=$query');
}

/// Bereitet den Trailnamen als Pin-Titel auf: Klammern sind das
/// Trennzeichen des Schemas und fallen weg (`Uri.encodeComponent` ließe
/// sie stehen), Leerraum wird zusammengefasst, Überlänge gekürzt.
String? _sanitizeLabel(String? label) {
  if (label == null) return null;
  var clean = label.replaceAll(RegExp(r'[()]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return null;
  if (clean.length > kMaxLabelLength) {
    clean = '${clean.substring(0, kMaxLabelLength).trimRight()}…';
  }
  return Uri.encodeComponent(clean);
}

/// Was beim Übergeben herausgekommen ist — die Oberfläche sagt es, denn
/// zwei der drei Fälle sähen sonst nach „nichts passiert" aus.
enum NavigationOutcome {
  /// Der App-Wähler bzw. die Navi-App ist offen — nichts zu melden.
  opened,

  /// Android, aber keine installierte App nimmt `geo:` an.
  copiedNoApp,

  /// Im Browser gibt es keinen App-Wähler.
  copiedInBrowser,
}

/// Öffnet den Ort in einer Navi-App; sonst liegt er in der Zwischenablage.
/// [launch] ist die Naht für Tests.
Future<NavigationOutcome> openInNavigationApp({
  required double lat,
  required double lng,
  String? label,
  Future<bool> Function(Uri)? launch,
}) async {
  if (!kIsWeb) {
    final open = launch ?? _launchExternally;
    try {
      if (await open(geoUriFor(lat: lat, lng: lng, label: label))) {
        return NavigationOutcome.opened;
      }
    } catch (_) {
      // Kein Programm für `geo:` — url_launcher meldet das je nach
      // Android-Fassung als `false` oder als Ausnahme. Beides ist hier
      // dasselbe und kein Fehler fürs Protokoll: Der Rückfallweg trägt.
    }
  }
  await Clipboard.setData(ClipboardData(text: formatCoordinates(lat, lng)));
  return kIsWeb ? NavigationOutcome.copiedInBrowser : NavigationOutcome.copiedNoApp;
}

Future<bool> _launchExternally(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Der Pin-Titel: der angezeigte Name, aber nicht der Platzhalter —
/// „Trail ohne Namen" als Ziel in einer fremden App sagt nichts.
String? navigationLabelOf(Trail trail) => trail.hasName ? trail.displayName : null;

/// Übergibt den Trailkopf von [trail] (Anfang in Trail-Richtung,
/// `Trail.start`) an eine Navi-App und sagt es, wenn das nicht geht.
///
/// Gemeldet wird nur, was der Nutzer sonst nicht sieht: Klappt der
/// App-Wähler auf, steht die andere App im Vordergrund und eine SnackBar
/// dahinter wäre für niemanden. Die beiden Rückfälle dagegen sähen ohne
/// Meldung aus wie ein Knopf, der nichts tut.
Future<void> navigateToTrailHead(BuildContext context, Trail trail) =>
    navigateToPoint(context, trail.start, name: navigationLabelOf(trail), trailHead: true);

/// Dasselbe für einen beliebigen Punkt (#177: „Route bis hier" mit der
/// Navi-App). [trailHead] wählt den Satz der Rückfälle („Koordinaten des
/// Trailkopfs …" statt „… des Ziels …") — ganze Sätze in den ARB-Dateien,
/// kein Satzteil, den eine andere Sprache anders beugt (#209).
Future<void> navigateToPoint(BuildContext context, LatLng point, {String? name, bool trailHead = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final outcome = await openInNavigationApp(lat: point.latitude, lng: point.longitude, label: name);
  if (outcome == NavigationOutcome.opened) return;
  final coordinates = formatCoordinates(point.latitude, point.longitude);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(switch ((outcome == NavigationOutcome.copiedNoApp, trailHead)) {
        (true, true) => l.navNoAppTrailHead(coordinates),
        (true, false) => l.navNoAppTarget(coordinates),
        (false, true) => l.navCopiedTrailHead(coordinates),
        (false, false) => l.navCopiedTarget(coordinates),
      }),
    ));
}
