import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../l10n/l10n.dart';

/// Eine ausgewählte Datei, wie sie aus der Dateiauswahl kommt — Name und
/// rohe Bytes. Ob GPX oder Zip, entscheidet erst [gpxFilesFrom].
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  /// Für Tests und für Aufrufer, die schon Text haben.
  PickedFile.text(this.name, String text)
      : bytes = Uint8List.fromList(utf8.encode(text));

  final String name;
  final Uint8List bytes;
}

/// Eine GPX-Datei als Text, bereit für `parseGpx`. Aus einem Zip trägt
/// sie den Namen ihres Eintrags, nicht den des Archivs — sonst hießen
/// 584 Trails aus einem Locus-Export alle „Trails.zip".
class PickedGpx {
  const PickedGpx({required this.name, required this.text});
  final String name;
  final String text;
}

/// Macht aus einer ausgewählten Datei die GPX-Texte darin: eine GPX-Datei
/// ist einer, ein Zip-Archiv so viele, wie `.gpx`-Einträge darin stehen
/// (Locus exportiert Tracks gezippt, Konzept 10, Punkt 5). Alles andere
/// ist ein Fehler mit Dateinamen — die Auswahl auf Android filtert nicht
/// (siehe `gpxPickerProvider`), also landet dort auch mal ein Foto.
///
/// Zip wird am Magic `PK\x03\x04` erkannt, nicht an der Endung: Manche
/// Dateimanager reichen den Namen ohne Endung durch. Die Fehlerzeilen
/// stehen so auf dem Schirm, daher [l] (#209).
({List<PickedGpx> files, List<String> errors}) gpxFilesFrom(AppLocalizations l, PickedFile file) {
  if (_isZip(file.bytes)) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(file.bytes);
    } catch (_) {
      // Das Archiv selbst ist kaputt; der Grund aus dem Decoder hilft
      // niemandem, der Dateiname schon.
      return (files: const [], errors: [l.gpxZipUnreadable(file.name)]);
    }
    // Ein Zip-Kopf mit Müll dahinter wirft nicht, er ergibt ein leeres
    // Archiv — für den Nutzer dasselbe wie „nicht lesbar".
    if (archive.files.isEmpty) {
      return (files: const [], errors: [l.gpxZipUnreadable(file.name)]);
    }
    final files = <PickedGpx>[];
    for (final entry in archive.files) {
      if (!entry.isFile || !_isGpxEntry(entry.name)) continue;
      files.add(PickedGpx(name: _baseName(entry.name), text: _decode(entry.content as List<int>)));
    }
    if (files.isEmpty) {
      return (files: const [], errors: [l.gpxZipNoGpx(file.name)]);
    }
    return (files: files, errors: const []);
  }
  if (!file.name.toLowerCase().endsWith('.gpx') && !_looksLikeXml(file.bytes)) {
    return (files: const [], errors: [l.gpxNotGpxOrZip(file.name)]);
  }
  return (files: [PickedGpx(name: file.name, text: _decode(file.bytes))], errors: const []);
}

bool _isZip(Uint8List b) =>
    b.length > 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

/// macOS legt beim Zippen `__MACOSX/._name.gpx` daneben — Ressourcen-
/// gabeln mit derselben Endung, aber ohne XML darin.
bool _isGpxEntry(String path) {
  final lower = path.toLowerCase();
  if (!lower.endsWith('.gpx')) return false;
  if (lower.startsWith('__macosx/') || lower.contains('/__macosx/')) return false;
  return !_baseName(lower).startsWith('._');
}

String _baseName(String path) => path.split('/').last;

/// Eine Datei ohne `.gpx`-Endung darf trotzdem GPX sein, wenn sie wie XML
/// anfängt; `parseGpx` sagt dann genauer, was nicht stimmt.
bool _looksLikeXml(Uint8List b) {
  final head = _decode(b.length > 64 ? b.sublist(0, 64) : b).trimLeft();
  return head.startsWith('<');
}

/// UTF-8 mit Nachsicht und ohne BOM: GPX ist fast immer UTF-8, und ein
/// einzelnes falsches Byte in einem Namen soll nicht den ganzen Track
/// kosten.
String _decode(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}
