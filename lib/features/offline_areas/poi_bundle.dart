// Das Orte-Bündel einer Region (#229, Konzept 8.6): eine gzip-Datei mit
// einer Kopfzeile (JSON: `format`, `build`, `files`) und je Zellendatei
// einer Zeile `<name>\t<inhalt>`. Der Inhalt ist Byte für Byte die
// Zellendatei, die selbst eine Zeile ist — zurück kommt sie also MIT dem
// Zeilenende. Geschrieben von `tool/poi_extract.py` (`write_bundle`).
//
// Zerlegt wird Zeile für Zeile beim Entpacken: Das ganze Bündel entpackt
// wären für DACH 165 MB Text auf einmal. Auf dem Telefon über `dart:io`
// im Strom; im Browser gibt es „Ganze Region" nicht, dort entpackt der
// Rückfall am Stück.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../map/poi.dart';
import 'poi_bundle_lines_web.dart' if (dart.library.io) 'poi_bundle_lines_io.dart';

/// Das Bündel passt nicht zu seinem Manifest oder ist kaputt — kein
/// Netzfehler; der Bereich bleibt unvollständig.
class PoiBundleMismatch implements Exception {
  const PoiBundleMismatch(this.message);
  final String message;
  @override
  String toString() => 'Orte-Bündel passt nicht: $message';
}

final _name = RegExp(r'^-?\d+_-?\d+\.[a-z]+\.json$');

/// Prüft Länge und Prüfsumme gegen [bundle] und liefert die Zellendateien
/// als (Name, Inhalt) — erst, wenn die Kopfzeile zum Bau [build] passt;
/// am Ende muss die Zahl stimmen, sonst wirft es.
Stream<(String, String)> readPoiBundle(Uint8List bytes, PoiBundle bundle, String build) async* {
  if (bytes.length != bundle.bytes) throw PoiBundleMismatch('${bytes.length} statt ${bundle.bytes} Bytes');
  final sha = crypto.sha256.convert(bytes).toString();
  if (sha != bundle.sha256) throw PoiBundleMismatch('Prüfsumme $sha');
  var header = true;
  var count = 0;
  await for (final line in gunzipLines(bytes)) {
    if (header) {
      header = false;
      final Object? h;
      try {
        h = jsonDecode(line);
      } on FormatException {
        throw const PoiBundleMismatch('Kopfzeile ist kein JSON');
      }
      if (h is! Map || h['format'] != 1 || h['build'] != build || h['files'] != bundle.files) {
        throw PoiBundleMismatch('Kopfzeile $line');
      }
      continue;
    }
    if (line.isEmpty) continue;
    final tab = line.indexOf('\t');
    final name = tab < 0 ? '' : line.substring(0, tab);
    if (!_name.hasMatch(name)) throw PoiBundleMismatch('Zeile ${count + 1}: kein Dateiname');
    count++;
    yield (name, '${line.substring(tab + 1)}\n');
  }
  if (header) throw const PoiBundleMismatch('leer');
  if (count != bundle.files) throw PoiBundleMismatch('$count statt ${bundle.files} Dateien');
}
