// Ein Foto am Hinweis (#37, Patch 026): eines je Hinweis, sichtbar für
// genau die, die den Hinweis sehen, 90 Tage. Die Stelle verlässt das Gerät
// nicht im Bild — was der Fake-Bucket bekommt, ist durch `preparePhoto`
// gegangen, und der Test liest die Bytes.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/photo_pipeline.dart';
import 'package:trailbuddy/core/photo_providers.dart';
import 'package:trailbuddy/core/widgets/photo_attachment.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId, carlaId;
  late String roots, bobsFlow;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    final carla = backend.addUser(username: 'carla');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    carlaId = carla.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    trails.usernames[carla.id] = 'carla';
    roots = trails.seedTrail(anna.id, name: 'Roots');
    bobsFlow = trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1);
  });

  /// Der Wähler liefert [picked] — ein Foto, wie es vom Telefon kommt.
  Future<void> openTrail(WidgetTester tester, String name, {Uint8List? picked}) async {
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      photoPickerProvider.overrideWithValue((_) async => picked),
    ]);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  Future<void> writeNote(WidgetTester tester, String text, {bool attach = true}) async {
    await tester.ensureVisible(find.byKey(const ValueKey('add-note')));
    await tester.tap(find.byKey(const ValueKey('add-note')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('note-text')), text);
    await settle(tester);
    if (attach) {
      await tester.tap(find.byKey(kAttachPhotoKey));
      await settle(tester, frames: 20);
    }
  }

  testWidgets('Hinweis mit Foto: ohne Ortsangaben hochgeladen, Vorschau im Blatt, Bild auf Tipp',
      (tester) async {
    await openTrail(tester, 'Roots', picked: dirtyJpeg(width: 2000, height: 1500));
    await writeNote(tester, 'Baum liegt quer');
    // Die Vorschau zeigt das ENTKERNTE Bild, und der Satz sagt, was bleibt.
    expect(find.bySemanticsLabel('Angehängtes Foto'), findsOneWidget);
    expect(find.textContaining('Ortsangaben im Bild werden entfernt'), findsOneWidget);
    expect(find.textContaining('90 Tage'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);
    expect(find.text('Hinweis mit Foto gespeichert'), findsOneWidget);

    final note = trails.notes.single;
    final photo = trails.notePhotos[note.id]!;
    expect(photo.key, startsWith('$annaId/'), reason: 'eigener Ordner, wie die Storage-Policy');
    final full = trails.notePhotoObjects[photo.fullPath]!;
    final thumb = trails.notePhotoObjects[photo.thumbPath]!;
    for (final bytes in [full, thumb]) {
      expect(jpegForeignMarkers(bytes), isEmpty);
      expect(hasText(bytes, 'Trailkopf'), isFalse);
      expect(hasText(bytes, 'Exif'), isFalse);
    }

    // Im Blatt steht die Vorschau; das große Bild lädt erst auf Tipp.
    final tile = find.byKey(ValueKey('note-photo-${note.id}'));
    await tester.ensureVisible(tile);
    expect(trails.notePhotoDownloads[photo.thumbPath], 1);
    expect(trails.notePhotoDownloads[photo.fullPath], isNull);
    await tester.tap(tile);
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('note-photo-view')), findsOneWidget);
    expect(trails.notePhotoDownloads[photo.fullPath], 1);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('note-photo-view')), matching: find.byIcon(Icons.close)));
    await settle(tester);
    expect(find.byKey(const ValueKey('note-photo-view')), findsNothing);
  });

  testWidgets('angehängtes Foto wieder entfernen: der Hinweis geht ohne', (tester) async {
    await openTrail(tester, 'Roots', picked: dirtyJpeg());
    await writeNote(tester, 'Neuer Drop');
    await tester.tap(find.byKey(kRemovePhotoKey));
    await settle(tester);
    expect(find.byKey(kAttachPhotoKey), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);
    expect(find.text('Hinweis gespeichert'), findsOneWidget);
    expect(trails.notePhotos, isEmpty);
    expect(trails.notePhotoObjects, isEmpty);
  });

  testWidgets('scheitert das Foto, steht der Hinweis trotzdem — und die Meldung sagt beides',
      (tester) async {
    await openTrail(tester, 'Roots', picked: dirtyJpeg());
    trails.failNextPhotoUpload = StateError('Speicher voll');
    await writeNote(tester, 'Baum liegt quer');
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);
    expect(find.textContaining('Hinweis gespeichert, das Foto aber nicht'), findsOneWidget);
    expect(trails.notes.single.body, 'Baum liegt quer');
    expect(trails.notePhotos, isEmpty);
    expect(find.text('Baum liegt quer'), findsOneWidget, reason: 'der Hinweis steht im Blatt');
  });

  testWidgets('was kein Bild ist, wird nicht angehängt und sagt warum', (tester) async {
    await openTrail(tester, 'Roots', picked: Uint8List.fromList([1, 2, 3, 4]));
    await writeNote(tester, 'Baum liegt quer');
    expect(find.textContaining('Bildformat'), findsOneWidget);
    expect(find.byKey(kAttachPhotoKey), findsOneWidget, reason: 'kein Bild angehängt');
  });

  testWidgets('das Foto eines Buddys: sichtbar wie sein Hinweis, „erledigt" nimmt es mit',
      (tester) async {
    final bobsNote = trails.seedNote(bobId, bobsFlow, 'Baum liegt quer');
    trails.seedNotePhoto(bobsNote, cleanJpeg(), cleanJpeg());
    // Carla ist keine Buddy — ihr Hinweis samt Foto bleibt unsichtbar.
    trails.seedTrail(carlaId, trailId: bobsFlow);
    final carlasNote = trails.seedNote(carlaId, bobsFlow, 'Von Carla');
    trails.seedNotePhoto(carlasNote, cleanJpeg(), cleanJpeg());
    await openTrail(tester, 'Bobs Flow');

    expect(find.byKey(ValueKey('note-photo-$bobsNote')), findsOneWidget);
    expect(find.byKey(ValueKey('note-photo-$carlasNote')), findsNothing);
    expect(find.text('Von Carla'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Erledigt — Hinweis entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Hinweis entfernen'));
    await settle(tester);
    expect(find.textContaining('samt Foto'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 20);
    expect(trails.notePhotos.containsKey(bobsNote), isFalse, reason: 'Cascade mit dem Hinweis');
    expect(find.byKey(ValueKey('note-photo-$bobsNote')), findsNothing);
  });

  testWidgets('ein abgelaufenes Foto zeigt das Blatt nicht mehr, der Hinweis bleibt',
      (tester) async {
    final mine = trails.seedNote(annaId, roots, 'Alter Baum');
    // Der eigene sieht die Zeile bis zum Abräumen — gezeigt wird sie nicht.
    trails.seedNotePhoto(mine, cleanJpeg(), cleanJpeg(),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)));
    await openTrail(tester, 'Roots');
    expect(find.text('Alter Baum'), findsOneWidget);
    expect(find.byKey(ValueKey('note-photo-$mine')), findsNothing);
    expect(trails.notePhotoDownloads, isEmpty, reason: 'nichts geladen');
  });
}
