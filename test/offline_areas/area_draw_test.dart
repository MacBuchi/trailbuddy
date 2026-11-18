// Bereiche zeichnen (Stufe C), pur: aus einem Strich die Kacheln, die er
// umschließt oder berührt; der Entwurf, der Striche addiert und abzieht,
// sich zurücknehmen lässt und nach dem Speichern verschwindet; und die
// Anzeige, die eine Zeile Kacheln zu EINEM Rechteck zieht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';

const _z = kAreaShapeZoom;

int _key(int x, int y) => TileSetShape.keyOf(x, y, _z);

/// Ein Ring knapp INNERHALB der Kacheln x0..x1 × y0..y1.
List<LatLng> _ringInside(int x0, int y0, int x1, int y1) {
  final nw = tileBounds(_z, x0, y0), se = tileBounds(_z, x1, y1);
  const e = 1e-5;
  return [
    LatLng(nw.north - e, nw.west + e),
    LatLng(nw.north - e, se.east - e),
    LatLng(se.south + e, se.east - e),
    LatLng(se.south + e, nw.west + e),
  ];
}

void main() {
  // Eine Kachel mitten in Oberbayern.
  final origin = tileAt(47.9, 11.6, _z);
  final x = origin.x, y = origin.y;

  test(
    'ein Ring innerhalb eines Kachelblocks: genau dieser Block, samt Innerem',
    () {
      final keys = tilesTouchedByRing(_ringInside(x, y, x + 4, y + 3))!;
      expect(keys, {
        for (var i = x; i <= x + 4; i++)
          for (var j = y; j <= y + 3; j++) _key(i, j),
      });
    },
  );

  test(
    'berührt heißt dabei: ein Ring über die Kachelgrenze nimmt die Nachbarn mit',
    () {
      final nw = tileBounds(_z, x, y), se = tileBounds(_z, x + 1, y + 1);
      // Ein Zehntel Kachel über den Block hinaus, nach Osten.
      final spill = (se.east - nw.west) / 20;
      final keys = tilesTouchedByRing([
        LatLng(nw.north - 1e-5, nw.west + 1e-5),
        LatLng(nw.north - 1e-5, se.east + spill),
        LatLng(se.south + 1e-5, se.east + spill),
        LatLng(se.south + 1e-5, nw.west + 1e-5),
      ])!;
      expect(keys, containsAll([_key(x + 2, y), _key(x + 2, y + 1)]));
      expect(keys, hasLength(6));
    },
  );

  test('ein L: die Ecke, die der Strich ausspart, bleibt draußen', () {
    // Block 4 × 4, oben rechts 2 × 2 ausgespart.
    final a = tileBounds(_z, x, y), b = tileBounds(_z, x + 3, y + 3);
    final mid = tileBounds(
      _z,
      x + 2,
      y + 2,
    ); // Ecke der Aussparung: NW von (x+2, y+2)
    const e = 1e-5;
    final keys = tilesTouchedByRing([
      LatLng(a.north - e, a.west + e),
      LatLng(a.north - e, mid.west - e),
      LatLng(mid.north - e, mid.west - e),
      LatLng(mid.north - e, b.east - e),
      LatLng(b.south + e, b.east - e),
      LatLng(b.south + e, a.west + e),
    ])!;
    expect(keys, hasLength(16 - 4));
    for (final k in [
      _key(x + 2, y),
      _key(x + 3, y),
      _key(x + 2, y + 1),
      _key(x + 3, y + 1),
    ]) {
      expect(keys, isNot(contains(k)));
    }
  });

  test(
    'ein offener Strich ist eine dünne Fläche: die Kacheln, über die er läuft',
    () {
      final a = tileBounds(_z, x, y), b = tileBounds(_z, x + 5, y);
      final row = (a.north + a.south) / 2;
      final keys = tilesTouchedByRing([
        LatLng(row, a.west + 1e-5),
        LatLng(row, b.east - 1e-5),
      ])!;
      expect(keys, {for (var i = x; i <= x + 5; i++) _key(i, y)});
    },
  );

  test('zu groß gezeichnet ⇒ null, zu wenig ⇒ nichts', () {
    expect(
      tilesTouchedByRing(const [
        LatLng(30, 0),
        LatLng(30, 30),
        LatLng(60, 30),
        LatLng(60, 0),
      ]),
      isNull,
    );
    expect(tilesTouchedByRing(const [LatLng(47.9, 11.6)]), isEmpty);
  });

  /// Ein Container, in dem [stored] der gespeicherte Bestand ist.
  ProviderContainer container(Set<int> stored) {
    final c = ProviderContainer(
      overrides: [storedTileKeysProvider.overrideWithValue(stored)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'der Entwurf rechnet gegen den Bestand: Gespeichertes kommt nicht dazu, Neues fällt nicht weg',
    () {
      // Gespeichert: x, x+1. Neu: x+2, x+3.
      final c = container({_key(x, y), _key(x + 1, y)});
      final n = c.read(areaDraftProvider.notifier);
      AreaDraft d() => c.read(areaDraftProvider)!;
      n.start();
      n.applyStroke({_key(x, y)});
      expect(d().isEmpty, isTrue, reason: 'ohne Werkzeug zählt kein Strich');

      n.arm(AreaDrawTool.add);
      expect(d().tool, AreaDrawTool.add);
      n.applyStroke({
        _key(x, y),
        _key(x + 1, y),
        _key(x + 2, y),
        _key(x + 3, y),
      });
      expect(d().adds, {
        _key(x + 2, y),
        _key(x + 3, y),
      }, reason: 'was liegt, kommt nicht noch einmal');
      expect(d().removes, isEmpty);
      expect(d().tool, isNull, reason: 'nach dem Strich ist das Werkzeug weg');

      n.arm(AreaDrawTool.remove);
      n.applyStroke({_key(x + 1, y), _key(x + 2, y), _key(x + 9, y)});
      expect(d().adds, {
        _key(x + 3, y),
      }, reason: 'eine offene Zugabe wird zurückgenommen');
      expect(d().removes, {
        _key(x + 1, y),
      }, reason: 'Gespeichertes fällt weg, Unbekanntes nicht');

      // Wieder dazu: nimmt das Wegfallen zurück.
      n.addAll({_key(x + 1, y)});
      expect(d().removes, isEmpty);
      expect(d().adds, {_key(x + 3, y)});

      // Derselbe Knopf noch einmal nimmt das Werkzeug zurück.
      n.arm(AreaDrawTool.add);
      n.arm(AreaDrawTool.add);
      expect(d().tool, isNull);

      n.undo();
      expect(d().removes, {_key(x + 1, y)});
      n.undo();
      n.undo();
      expect(d().isEmpty, isTrue);
      expect(d().history, isEmpty);

      // Nach einem halben Speichern bleibt nur „kommt dazu".
      n.addAll({_key(x + 5, y)});
      n.removeAll({_key(x, y)});
      n.dropRemoves();
      expect(d().adds, {_key(x + 5, y)});
      expect(d().removes, isEmpty);
      n.clear();
      expect(d().isEmpty, isTrue);
      expect(n.hasChanges, isFalse);
    },
  );

  test(
    'ein Strich ohne Änderung ist kein Schritt — Rückgängig tut immer etwas',
    () {
      final c = container(const {});
      final n = c.read(areaDraftProvider.notifier)..start();
      n.arm(AreaDrawTool.remove);
      n.applyStroke({_key(x, y)});
      expect(c.read(areaDraftProvider)!.history, isEmpty);
      expect(c.read(areaDraftProvider)!.tool, isNull);
    },
  );

  test('Schnappschuss: die 13er-Kacheln des Ausschnitts, zu groß ⇒ null', () {
    final b = tileBounds(_z, x, y);
    final keys = tilesInBounds(
      AreaBounds(
        south: b.south + 1e-6,
        west: b.west + 1e-6,
        north: b.north - 1e-6,
        east: tileBounds(_z, x + 2, y).east - 1e-6,
      ),
    )!;
    expect(keys, {_key(x, y), _key(x + 1, y), _key(x + 2, y)});
    expect(
      tilesInBounds(const AreaBounds(south: 30, west: 0, north: 60, east: 30)),
      isNull,
    );
  });

  test('Werkzeuge und „dazunehmen" beginnen den Entwurf selbst', () {
    final c = container(const {});
    final n = c.read(areaDraftProvider.notifier);
    expect(n.hasChanges, isFalse);
    n.addAll({_key(x, y)});
    expect(n.hasChanges, isTrue);
    n.discard();
    n.arm(AreaDrawTool.add);
    expect(c.read(areaDraftProvider)!.tool, AreaDrawTool.add);
    expect(
      n.hasChanges,
      isFalse,
      reason: 'ein Werkzeug allein ist keine Änderung',
    );
  });

  group(
    'Schraffur (Design Turn 2: dazu hell auf dunkel, weg dunkel auf hell, gespiegelt)',
    () {
      final rect = tileBounds(_z, x, y);
      const zoom = 14.0;

      test(
        'die Linien liegen im Rechteck, laufen diagonal, und gespiegelt in die andere Richtung',
        () {
          final lines = hatchLines([rect], zoom, mirrored: false)!;
          final mirrored = hatchLines([rect], zoom, mirrored: true)!;
          expect(lines, isNotEmpty);
          expect(mirrored, isNotEmpty);
          for (final l in [...lines, ...mirrored]) {
            for (final p in l) {
              expect(
                p.latitude,
                inInclusiveRange(rect.south - 1e-9, rect.north + 1e-9),
              );
              expect(
                p.longitude,
                inInclusiveRange(rect.west - 1e-9, rect.east + 1e-9),
              );
            }
          }
          // `/`: nach Osten geht es nach Norden. Gespiegelt: nach Süden.
          bool rising(List<LatLng> l) {
            final a = l.first, b = l.last;
            return (b.longitude - a.longitude) * (b.latitude - a.latitude) > 0;
          }

          expect(lines.every(rising), isTrue);
          expect(mirrored.every((l) => !rising(l)), isTrue);
          // Eine 13er-Kachel ist bei Zoom 14 zweimal 256 px, bei 7 px Abstand
          // also rund 146 Linien (Diagonalen über 512 + 512 px).
          expect(lines.length, inInclusiveRange(140, 152));
        },
      );

      test(
        'die Linien hängen am Weltraster: zwei Hälften ergeben dieselben Linien wie das Ganze',
        () {
          final left = tileBounds(_z, x, y), right = tileBounds(_z, x + 1, y);
          final whole = AreaBounds(
            south: left.south,
            west: left.west,
            north: left.north,
            east: right.east,
          );
          int count(List<List<LatLng>>? l) => l!.length;
          // Jede Linie, die über die Naht läuft, zerfällt in zwei — mehr nicht.
          final split =
              count(hatchLines([left], zoom, mirrored: false)) +
              count(hatchLines([right], zoom, mirrored: false));
          final one = count(hatchLines([whole], zoom, mirrored: false));
          expect(split - one, inInclusiveRange(0, 75));
        },
      );

      test(
        'die Tinte ist hell bzw. dunkel und farblos — eine Regel, keine neue Farbe',
        () {
          final light = HSLColor.fromColor(kAreaInkLight),
              dark = HSLColor.fromColor(kAreaInkDark);
          expect(light.lightness, greaterThan(0.85));
          expect(dark.lightness, lessThan(0.15));
          // Kein Grün, kein Rot: fast grau (#131A16 hat einen Hauch Grün,
          // bei 9 % Helligkeit unsichtbar).
          for (final c in [kAreaInkLight, kAreaInkDark]) {
            expect(
              (c.r - c.g).abs() + (c.g - c.b).abs(),
              lessThan(0.06),
              reason: '$c',
            );
          }
        },
      );

      test('zu viele Linien ⇒ null, dann gilt der Rückfall 2e', () {
        expect(hatchLines([rect], zoom, mirrored: false, maxLines: 10), isNull);
      });

      test(
        'auf der Karte: hell schraffiert dazu, dunkel gespiegelt weg, je ein gestrichelter Rand — kein Grün, kein Rot',
        () {
          final draft = AreaDraft(
            adds: {_key(x, y), _key(x + 1, y)},
            removes: {_key(x + 3, y)},
          );
          final center = tileBounds(_z, x + 2, y).center;
          MapViewCamera cam(double half, double width) => MapViewCamera(
            center: center,
            bounds: MapViewBounds(
              west: center.longitude - half,
              east: center.longitude + half,
              south: center.latitude - half / 2,
              north: center.latitude + half / 2,
            ),
            size: Size(width, width / 2),
          );
          Iterable<MapViewPolyline> hatch(List<MapViewPolyline> l, Color c) =>
              l.where((l) => l.color == c && l.dash == null);
          Iterable<MapViewPolyline> border(List<MapViewPolyline> l, Color c) =>
              l.where((l) => l.color == c && l.dash != null);

          final near = draftLayers(draft, cam(0.1, 800));
          expect(
            near.polygons,
            isEmpty,
            reason: 'den Grund liefert die Maske, hier nur die Zeichnung',
          );
          expect(hatch(near.lines, kAreaInkLight), isNotEmpty);
          expect(hatch(near.lines, kAreaInkDark), isNotEmpty);
          expect(
            border(near.lines, kAreaInkLight),
            hasLength(4),
            reason: 'zwei Kacheln nebeneinander: ein Rechteck',
          );
          expect(border(near.lines, kAreaInkDark), hasLength(4));
          expect(near.lines.map((l) => l.color).toSet(), {
            kAreaInkLight,
            kAreaInkDark,
          }, reason: 'eine Regel, keine neue Farbe');
          expect(
            near.lines.every((l) => l.hitValue == null),
            isTrue,
            reason: 'ein Tipp geht hindurch',
          );
          // Die Ränder liegen über der Schraffur.
          final firstBorder = near.lines.indexWhere((l) => l.dash != null);
          expect(
            near.lines.skip(firstBorder).every((l) => l.dash != null),
            isTrue,
          );

          // Weit draußen: dieselben Ränder, die Schraffur ist ein Strich je
          // Kachel — und ohne Linien nichts zu tönen.
          final far = draftLayers(draft, cam(3, 400));
          expect(border(far.lines, kAreaInkLight), hasLength(4));
          expect(far.polygons, isEmpty);

          // Zu viele Linien (ein großer Block, nah dran): Rückfall 2e — halbe
          // Tönung, der Rand bleibt und unterscheidet allein.
          final block = AreaDraft(
            adds: {
              for (var i = -10; i < 0; i++)
                for (var j = -10; j < 10; j++) _key(x + i, y + j),
            },
            removes: {
              for (var i = 1; i < 10; i++)
                for (var j = -10; j < 10; j++) _key(x + i, y + j),
            },
          );
          final dense = draftLayers(block, cam(0.1, 8000));
          expect(
            dense.lines.where((l) => l.dash == null),
            isEmpty,
            reason: 'keine Schraffur',
          );
          expect(
            dense.polygons.where((p) => p.fillColor == kAreaAddHalfTone),
            isNotEmpty,
          );
          expect(
            dense.polygons.where((p) => p.fillColor == kAreaRemoveHalfTone),
            isNotEmpty,
          );
          expect(border(dense.lines, kAreaInkLight), isNotEmpty);
          expect(border(dense.lines, kAreaInkDark), isNotEmpty);
          expect(draftLayers(AreaDraft(), cam(0.1, 800)).lines, isEmpty);
        },
      );
    },
  );
}
