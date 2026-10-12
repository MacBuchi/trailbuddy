// Was aus einer ausgewählten Datei wird (gpx_files.dart). Die Auswahl auf
// Android filtert nicht mehr (Feldbefund v0.1.0), also muss das hier
// jede Sorte Datei vertragen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import '../fakes/l10n_de.dart';

const _gpx = '<gpx version="1.1"><trk><name>A</name><trkseg>'
    '<trkpt lat="48.0" lon="9.0"/><trkpt lat="48.01" lon="9.0"/></trkseg></trk></gpx>';

Uint8List _zip(Map<String, String> entries) {
  final a = Archive();
  entries.forEach((name, text) => a.addFile(ArchiveFile.string(name, text)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test('eine GPX-Datei ist ein Text', () {
    final r = gpxFilesFrom(l10nDe, PickedFile.text('a.gpx', _gpx));
    expect(r.errors, isEmpty);
    expect(r.files.single.name, 'a.gpx');
    expect(r.files.single.text, _gpx);
  });

  test('ein BOM fällt weg, kaputte Bytes kosten nicht die Datei', () {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(_gpx), 0xFF]);
    final r = gpxFilesFrom(l10nDe, PickedFile(name: 'a.gpx', bytes: bytes));
    expect(r.files.single.text, startsWith('<gpx'));
  });

  test('ein Zip liefert jede GPX darin, unter ihrem eigenen Namen', () {
    final r = gpxFilesFrom(l10nDe, PickedFile(
      name: 'Trails.zip',
      bytes: _zip({'a/eins.gpx': _gpx, 'zwei.GPX': _gpx, 'notiz.txt': 'x'}),
    ));
    expect(r.errors, isEmpty);
    expect(r.files.map((f) => f.name), unorderedEquals(['eins.gpx', 'zwei.GPX']));
  });

  test('Zip wird am Inhalt erkannt, nicht an der Endung', () {
    final r = gpxFilesFrom(l10nDe, PickedFile(name: 'download', bytes: _zip({'x.gpx': _gpx})));
    expect(r.files, hasLength(1));
  });

  test('macOS-Ressourcengabeln zählen nicht als GPX', () {
    final r = gpxFilesFrom(l10nDe, PickedFile(
      name: 'mac.zip',
      bytes: _zip({'__MACOSX/._x.gpx': 'binär', 'x/._y.gpx': 'binär', 'x.gpx': _gpx}),
    ));
    expect(r.files.map((f) => f.name), ['x.gpx']);
  });

  test('ein Zip ohne GPX wird benannt', () {
    final r = gpxFilesFrom(l10nDe, PickedFile(name: 'fotos.zip', bytes: _zip({'a.jpg': 'x'})));
    expect(r.files, isEmpty);
    expect(r.errors.single, 'fotos.zip: keine GPX-Datei im Archiv.');
  });

  test('ein kaputtes Zip wird benannt, nicht geworfen', () {
    final bytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6]);
    final r = gpxFilesFrom(l10nDe, PickedFile(name: 'kaputt.zip', bytes: bytes));
    expect(r.errors.single, 'kaputt.zip: Zip-Archiv ist leer oder nicht lesbar.');
  });

  test('Fremdes wird abgewiesen, XML ohne Endung darf zum Parser', () {
    expect(gpxFilesFrom(l10nDe, PickedFile.text('bild.jpg', 'JFIF')).errors.single,
        'bild.jpg: weder GPX noch Zip.');
    expect(gpxFilesFrom(l10nDe, PickedFile.text('export', '  $_gpx')).files, hasLength(1));
  });

  test('die Auswahl filtert auf Android nicht nach MIME-Typ', () {
    // Mit `application/gpx+xml` waren GPX und Zip im System-Dialog
    // ausgegraut — die Zeile kommt nicht wieder.
    final src = File('lib/features/trails/trail_import_screen.dart').readAsStringSync();
    expect(src, isNot(contains("'application/gpx+xml'")));
    expect(src, contains("mimeTypes: ['*/*']"));
    expect(src, contains("extensions: ['gpx', 'zip']"));
  });
}
