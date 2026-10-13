// Die Stelle verlässt das Gerät nicht im Foto (#37, aus PilzBuddy #532).
//
// **Der Test liest Bytes, keine Rückgabewerte.** Ein Aufruf, der „hat
// EXIF entfernt" meldet, wäre dieselbe Sorte Zusage wie „der Kodierer
// lässt es weg" — und genau die hat sich zweimal als falsch erwiesen
// (`image_picker` kopiert GPS zurück, `package:image` reicht es durch).
// Deshalb geht hier ein Bild hinein, das nachweislich GPS-EXIF, XMP und
// einen Kommentar trägt, und heraus kommen Bytes, die von Hand
// durchsucht werden.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:trailbuddy/core/photo_pipeline.dart';

import '../fakes/l10n_de.dart';
import '../fakes/photo_fixtures.dart';

void main() {
  test('das Rohbild trägt wirklich, was entfernt werden soll', () {
    // Sonst prüfte der eigentliche Test ein leeres Versprechen.
    final dirty = dirtyJpeg();
    expect(jpegForeignMarkers(dirty), containsAll(['APP1', 'COM']));
    expect(hasText(dirty, 'Exif'), isTrue);
    expect(hasText(dirty, 'xmpmeta'), isTrue);
    expect(hasText(dirty, 'Trailkopf'), isTrue);
    final decoded = img.decodeJpg(dirty)!;
    expect(decoded.exif.gpsIfd.containsKey(0x0002), isTrue,
        reason: 'GPSLatitude steht im EXIF des Rohbilds');
    expect(decoded.exif.imageIfd['Make'].toString(), 'Testphone');
  });

  test('beide Ausgaben sind nackt: kein EXIF, kein XMP, kein Kommentar',
      () {
    final prepared = preparePhoto(dirtyJpeg());
    for (final (name, bytes) in [
      ('Bild', prepared.full),
      ('Vorschau', prepared.thumb)
    ]) {
      expect(jpegForeignMarkers(bytes), isEmpty,
          reason: '$name trägt ein fremdes Segment');
      expect(hasText(bytes, 'Exif'), isFalse, reason: name);
      expect(hasText(bytes, 'xmpmeta'), isFalse, reason: name);
      expect(hasText(bytes, 'Trailkopf'), isFalse, reason: name);
      expect(hasText(bytes, 'Testphone'), isFalse, reason: name);
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.exif.gpsIfd.containsKey(0x0002), isFalse,
          reason: '$name: GPSLatitude überlebt');
      expect(decoded.exif.isEmpty, isTrue, reason: '$name: EXIF überlebt');
    }
  });

  test('verkleinert auf die längste Kante, vergrößert nie', () {
    final prepared = preparePhoto(dirtyJpeg(width: 4000, height: 3000));
    expect((prepared.width, prepared.height), (kPhotoMaxEdge, 768));
    final thumb = img.decodeJpg(prepared.thumb)!;
    expect((thumb.width, thumb.height), (kPhotoThumbEdge, 150));

    final tall = preparePhoto(dirtyJpeg(width: 600, height: 2400));
    expect((tall.width, tall.height), (256, kPhotoMaxEdge));

    final small = preparePhoto(dirtyJpeg(width: 300, height: 200));
    expect((small.width, small.height), (300, 200), reason: 'nicht vergrößert');
  });

  test('die Drehung wird eingebacken, bevor EXIF wegfällt', () {
    // Orientierung 6: das Bild liegt um 90° gedreht auf dem Sensor und
    // muss zur Anzeige im Uhrzeigersinn gedreht werden. Danach steht die
    // weiße Ecke oben RECHTS — und ohne EXIF sagt nur noch das Bild
    // selbst, wo oben ist.
    final prepared = preparePhoto(dirtyJpeg(orientation: 6));
    expect((prepared.width, prepared.height), (480, 640));
    final image = img.decodeJpg(prepared.full)!;
    final topRight = image.getPixel(image.width - 10, 10);
    final topLeft = image.getPixel(10, 10);
    expect(topRight.r > 240 && topRight.g > 240, isTrue,
        reason: 'weiße Ecke oben rechts: $topRight');
    expect(topLeft.r > 240 && topLeft.g > 240, isFalse,
        reason: 'oben links ist nicht mehr weiß: $topLeft');
  });

  test('was kein Bild ist, scheitert mit einem Satz für den Nutzer', () {
    final says = throwsA(isA<PhotoPipelineException>()
        .having((e) => e.unreadable, 'unreadable', isTrue)
        .having((e) => e.userMessage(l10nDe), 'userMessage', contains('Bildformat')));
    expect(() => preparePhoto(Uint8List.fromList(utf8.encode('kein Bild'))),
        says);
    // Vier Bytes: Hier antwortet der Dekodierer nicht mit `null`,
    // sondern mit einem RangeError — im Flow-Test als „Unerwarteter
    // Fehler (RangeError)" gesehen.
    expect(() => preparePhoto(Uint8List.fromList([1, 2, 3, 4])), says);
    expect(() => preparePhoto(Uint8List(0)), says);
  });

  group('jpegForeignMarkers', () {
    test('ein sauberes JPEG meldet nichts', () {
      final clean = img.encodeJpg(img.Image(width: 8, height: 8));
      expect(jpegForeignMarkers(clean), isEmpty);
    });

    test('Bytes hinter dem EOI fallen auf', () {
      // Manche Telefone hängen dort Bewegtbild oder Tiefendaten an —
      // kein Segment, aber Daten.
      final clean = img.encodeJpg(img.Image(width: 8, height: 8));
      final trailer = Uint8List.fromList([...clean, ...utf8.encode('MotionPhoto')]);
      expect(jpegForeignMarkers(trailer), ['Anhang nach EOI (11 Bytes)']);
    });

    test('jedes fremde Segment wird beim Namen genannt', () {
      final clean = img.encodeJpg(img.Image(width: 8, height: 8));
      final dirty = withSegments(clean, [
        segment(0xE1, utf8.encode('Exif')),
        segment(0xE2, utf8.encode('ICC_PROFILE')),
        segment(0xED, utf8.encode('Photoshop 3.0')),
        segment(0xFE, utf8.encode('Kommentar')),
      ]);
      expect(jpegForeignMarkers(dirty), ['APP1', 'APP2', 'APP13', 'COM']);
    });

    test('kein JPEG, abgeschnitten, ohne EOI', () {
      expect(jpegForeignMarkers(Uint8List.fromList([1, 2, 3, 4])),
          ['kein JPEG']);
      final clean = img.encodeJpg(img.Image(width: 8, height: 8));
      expect(jpegForeignMarkers(clean.sublist(0, clean.length - 2)),
          ['kein EOI']);
      expect(jpegForeignMarkers(clean.sublist(0, 5)), ['abgeschnitten']);
    });
  });
}
