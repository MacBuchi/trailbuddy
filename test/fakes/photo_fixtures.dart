// Bilder für Tests, die Metadaten tragen — oder eben nicht.
//
// Geteilt zwischen dem Pipeline-Test (Bytes rein, Bytes raus) und den
// Flow-Tests (Bytes rein, Oberfläche und Fake-Bucket raus). Ein
// Fixture, damit beide dasselbe Rohbild meinen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ein Segment `FF <marker> <len> <payload>`.
Uint8List segment(int marker, List<int> payload) {
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, marker, len >> 8, len & 0xFF, ...payload]);
}

/// Schiebt [segments] direkt hinter den SOI von [jpeg].
Uint8List withSegments(Uint8List jpeg, List<Uint8List> segments) =>
    Uint8List.fromList([
      0xFF, 0xD8,
      for (final s in segments) ...s,
      ...jpeg.sublist(2),
    ]);

bool hasText(Uint8List bytes, String text) =>
    latin1.decode(bytes).contains(text);

/// Ein Foto, wie es vom Telefon kommt: mit Hersteller, Drehung,
/// GPS-Koordinate, XMP-Block und Kommentar — jedes davon ein anderer
/// Weg, auf dem eine Stelle im Bild stehen kann.
///
/// Oben links eine weiße Ecke, damit sich die Drehung prüfen lässt.
Uint8List dirtyJpeg({int width = 640, int height = 480, int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 120, 40));
  img.fillRect(image,
      x1: 0, y1: 0, x2: 60, y2: 60, color: img.ColorRgb8(255, 255, 255));
  image.exif.imageIfd['Make'] = 'Testphone';
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  // GPS-IFD: Breite als Rational, Referenz als ASCII — die Tags, die
  // `ExifDataCopier.java` zurückkopiert.
  image.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
  image.exif.gpsIfd[0x0002] = img.IfdValueRational(49, 1);
  image.exif.gpsIfd[0x0003] = img.IfdValueAscii('E');
  image.exif.gpsIfd[0x0004] = img.IfdValueRational(7, 1);
  final jpeg = img.encodeJpg(image, quality: 90);
  final xmp = segment(0xE1, [
    ...utf8.encode('http://ns.adobe.com/xap/1.0/'), 0,
    ...utf8.encode('<x:xmpmeta><rdf:Description exif:GPSLatitude="49,26.5N"'
        ' exif:GPSLongitude="7,30E"/></x:xmpmeta>'),
  ]);
  final comment =
      segment(0xFE, utf8.encode('Aufgenommen am Trailkopf, 49.44N 7.5E'));
  return withSegments(jpeg, [xmp, comment]);
}

/// Ein kleines, sauberes JPEG — was nach der Pipeline im Bucket liegt.
Uint8List cleanJpeg({int width = 32, int height = 32}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 160, 80));
  return img.encodeJpg(image, quality: 80);
}
