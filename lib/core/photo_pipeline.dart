// Fotos am Hinweis: verkleinern und von allem befreien, was nicht Bild
// ist (#37). Übernommen aus PilzBuddy (`lib/core/photo_pipeline.dart`,
// Fundfotos #532), dort im Quelltext der Bibliotheken nachgelesen.
//
// **Der Anlass ist eine Koordinate.** Ein Foto vom Telefon trägt in
// seinen Metadaten die Stelle, an der es entstand — beim Foto vom Baum
// quer über dem Trail die Stelle am Trail, beim Foto, das jemand aus der
// Galerie nimmt, womöglich die Haustür. Eine Fahrt beginnt an der
// Haustür, und genau deshalb verlässt in dieser App keine Fahrt das
// Gerät (Konzept 3). Ein geteiltes Foto gäbe einem Buddy die Stelle in
// die Hand — stumm, ohne dass ein Bildschirm es sagt.
//
// **„Der Kodierer lässt sie weg" ist ein Versprechen, keine
// Beobachtung.** Zwei Befunde aus PilzBuddy (2026-09-22):
//   - `image_picker` kopiert beim Verkleinern auf Android ABSICHTLICH
//     alle GPS-Tags in das verkleinerte Bild zurück
//     (`ExifDataCopier.java`).
//   - `package:image` reicht EXIF durch `bakeOrientation` und
//     `copyResize` hindurch und schreibt es in `encodeJpg` wieder
//     hinein, sobald `image.exif` nicht leer ist.
// Ein Weg, der auf einen von beiden vertraut, verschickt die Stelle.
// Deshalb wird hier erstens `exif` ausdrücklich geleert und zweitens
// das ERGEBNIS gelesen: [jpegForeignMarkers] geht die Segmente des
// fertigen JPEGs ab, und alles außer dem, was ein Bild zum Bild
// braucht, lässt [preparePhoto] scheitern — bei jedem Upload, nicht nur
// im Test. `test/photo_pipeline_test.dart` füttert ein Bild mit
// GPS-EXIF, XMP und Kommentar hinein und liest die Bytes zurück.
//
// Reines Dart, ohne Flutter: läuft im Isolate (`compute`) und auf der
// Test-VM ohne Binding.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../l10n/l10n.dart';

/// Längste Kante des geteilten Bildes.
///
/// 1024 statt 800 aus dem Issue: Die Vergrößerung zeigt das Bild mit
/// 16 px Rand auf ~380 dp, bei dreifacher Dichte also ~1150 px — 800
/// wären dort sichtbar weich. Bei Qualität 80 sind das rund 150 KB,
/// klein genug für den Free-Plan (1 GB Storage, 5 GB Egress im Monat).
const kPhotoMaxEdge = 1024;

/// Längste Kante der Vorschau — das, was das Trail-Blatt lädt.
///
/// Die Kachel am Hinweis ist 64 dp, dreifach also 192 px; 200 reicht, weil
/// `cover` ohnehin zuschneidet. Rund 12 KB statt 150: Die Vorschau ist der
/// Egress-Hebel, denn sie wird bei jedem Öffnen des Blatts geladen, das
/// volle Bild nur auf Tipp.
const kPhotoThumbEdge = 200;

const kPhotoJpegQuality = 80;
const kPhotoThumbJpegQuality = 75;

/// Das Ergebnis: zwei JPEGs ohne Metadaten und die Maße des großen.
typedef PreparedPhoto = ({
  Uint8List full,
  Uint8List thumb,
  int width,
  int height,
});

/// Warum ein Bild nicht geteilt werden kann. Der Satz für den Nutzer
/// kommt aus [userMessage] (#209); [toString] bleibt der technische Text
/// für den Digest.
class PhotoPipelineException implements Exception {
  /// Der Dekodierer kennt das Format nicht — kein Fehler der App.
  const PhotoPipelineException.unreadable() : details = null;

  /// Nach dem Entkernen steckt noch etwas im Bild; [details] nennt die
  /// Fundstellen.
  const PhotoPipelineException.metadata(String this.details);

  final String? details;

  bool get unreadable => details == null;

  String userMessage(AppLocalizations l) =>
      unreadable ? l.errorPhotoUnreadable : l.errorPhotoMetadata(details!);

  @override
  String toString() => unreadable
      ? 'PhotoPipelineException: Bildformat nicht lesbar'
      : 'PhotoPipelineException: Metadaten übrig ($details)';
}

/// Macht aus einem Foto zwei metadatenfreie JPEGs.
///
/// Wirft [PhotoPipelineException], wenn das Bild nicht lesbar ist —
/// oder wenn das Ergebnis wider Erwarten noch Metadaten trägt. Der
/// zweite Fall ist der, für den es diese Funktion gibt: Er darf nie
/// still durchgehen.
///
/// Top-Level und mit genau einem Argument, damit `compute` sie nehmen
/// kann.
PreparedPhoto preparePhoto(Uint8List original) =>
    _prepare(original, kPhotoMaxEdge, kPhotoJpegQuality);

PreparedPhoto _prepare(Uint8List original, int maxEdge, int quality) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } catch (_) {
    // Der Dekodierer stolpert über Müll nicht immer mit `null`, sondern
    // auch mit einem RangeError (vier Bytes reichen dafür). Für den
    // Nutzer ist beides dasselbe: kein Bild.
    decoded = null;
  }
  if (decoded == null) {
    throw const PhotoPipelineException.unreadable();
  }
  // Erst aufrichten: Die Drehung steht als EXIF-Tag im Bild, und gleich
  // wird EXIF weggeworfen — ein Bild, das danach auf der Seite liegt,
  // wäre die stille Folge.
  final upright = img.bakeOrientation(decoded);
  // **Hier fällt es weg, und nur hier.** `bakeOrientation` hat alles
  // außer der Drehung kopiert, `copyResize` würde es weiterreichen, und
  // `encodeJpg` schriebe es wieder hinein. Die Zeile ist die eine, die
  // die Stelle aus dem Bild nimmt — und der Test darunter ist die,
  // die es nachmisst.
  upright.exif = img.ExifData();

  final full = _shrink(upright, maxEdge);
  final thumb = _shrink(upright, kPhotoThumbEdge);
  final fullBytes = img.encodeJpg(full, quality: quality);
  final thumbBytes = img.encodeJpg(thumb, quality: kPhotoThumbJpegQuality);

  for (final (name, bytes) in [('Bild', fullBytes), ('Vorschau', thumbBytes)]) {
    final foreign = jpegForeignMarkers(bytes);
    if (foreign.isNotEmpty) {
      throw PhotoPipelineException.metadata('$name: ${foreign.join(', ')}');
    }
  }
  return (
    full: fullBytes,
    thumb: thumbBytes,
    width: full.width,
    height: full.height,
  );
}

/// Verkleinert auf [maxEdge] an der längsten Kante — nie vergrößern.
img.Image _shrink(img.Image image, int maxEdge) {
  if (math.max(image.width, image.height) <= maxEdge) return image;
  return image.width >= image.height
      ? img.copyResize(image,
          width: maxEdge, interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: maxEdge, interpolation: img.Interpolation.average);
}

/// Die Segmente, die ein JPEG zum Bild braucht — und sonst keines.
///
/// Eine ERLAUBNISLISTE, keine Verbotsliste: Ein neues Segment, das
/// irgendein Kodierer eines Tages schreibt, fällt so auf, statt
/// durchzurutschen. SOI, JFIF (APP0), Quantisierung, Frame-Kopf,
/// Huffman-Tabellen, Restart-Intervall, Scan, EOI.
const _allowedMarkers = {
  0xD8, // SOI
  0xE0, // APP0 — JFIF, trägt nur Dichte und Version
  0xDB, // DQT
  0xC0, 0xC1, 0xC2, // SOF0–2: Baseline, erweitert, progressiv
  0xC4, // DHT
  0xDD, // DRI
  0xDA, // SOS
  0xD9, // EOI
};

/// Alles in [bytes], was NICHT zum Bild gehört — leer heißt sauber.
///
/// Geht die Segmente des JPEGs ab und nennt jeden Marker, der nicht in
/// [_allowedMarkers] steht: `APP1` (EXIF und XMP), `APP13` (IPTC),
/// `COM` (Kommentar) und so weiter. Dazu zwei Fälle, die kein Segment
/// sind und trotzdem Daten tragen: Bytes HINTER dem EOI (manche
/// Telefone hängen dort Bewegtbild oder Tiefendaten an) und ein
/// Strom, der gar kein JPEG ist.
///
/// Wirft nie — wer eine Datei prüft, will eine Antwort, keinen zweiten
/// Fehler.
List<String> jpegForeignMarkers(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return const ['kein JPEG'];
  }
  final found = <String>[];
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      return [...found, 'Segmentgrenze verloren bei Byte $i'];
    }
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      // Füllbyte vor einem Marker — erlaubt, trägt nichts.
      i++;
      continue;
    }
    if (marker == 0xD9) {
      final trailing = bytes.length - (i + 2);
      if (trailing > 0) found.add('Anhang nach EOI ($trailing Bytes)');
      return found;
    }
    if (marker == 0xDA) {
      // Scan: Kopf überspringen, dann die Bilddaten, bis der nächste
      // echte Marker kommt. Darin ist `FF 00` ein gestopftes Datenbyte
      // und `FF D0`–`FF D7` ein Restart — beides kein Segment.
      if (i + 3 >= bytes.length) return [...found, 'abgeschnitten'];
      i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
      while (i + 1 < bytes.length) {
        final next = bytes[i + 1];
        if (bytes[i] == 0xFF && next != 0 && (next < 0xD0 || next > 0xD7)) {
          break;
        }
        i++;
      }
      continue;
    }
    if (!_allowedMarkers.contains(marker)) found.add(_markerName(marker));
    if (i + 3 >= bytes.length) return [...found, 'abgeschnitten'];
    i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
  }
  return [...found, 'kein EOI'];
}

String _markerName(int marker) {
  if (marker >= 0xE0 && marker <= 0xEF) return 'APP${marker - 0xE0}';
  if (marker == 0xFE) return 'COM';
  if (marker >= 0xC0 && marker <= 0xCF) return 'SOF${marker - 0xC0}';
  return 'FF${marker.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}
