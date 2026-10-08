// Die Ebene „Wege" (#212): Manifest, Stil-Ebenen beider Engines und die
// Zusagen aus `docs/design/README.md` Abschnitt 5a — nie eine Trail-Farbe,
// jede Breite über der Basislinie, im Web kein Strich.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/base_map_providers.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/features/map/way_layer.dart';

import '../fakes/fake_settings.dart';

/// Das Manifest, wie `tool/way_archive.py write_archive` es schreibt.
Map<String, dynamic> _toolManifest() => {
      'attribution': '© OpenStreetMap contributors (ODbL)',
      'bbox': [5.5, 45.5, 17.5, 55.5],
      'build': '20261101',
      'bytes': 92300000,
      'file': 'ways-20261101.pmtiles',
      'format': 2,
      'sha256': 'ab' * 32,
      'source': 'OpenStreetMap',
      'tiles': 53615,
      'zoom': 13,
    };

void main() {
  group('Manifest', () {
    test('liest, was das Werkzeug schreibt', () {
      final m = WaysManifest.fromJson(_toolManifest());
      expect(m.file, 'ways-20261101.pmtiles');
      expect(m.build, '20261101');
      expect(m.archiveUri.toString(), 'https://tiles.mcbuchi.de/trailbuddy/ways-20261101.pmtiles');
    });

    test('lehnt fremde Namen, Formate und Zoomstufen ab', () {
      for (final bad in [
        {..._toolManifest(), 'file': '../dach-20261101.pmtiles'},
        // Format 1 (bis 0.90.0) kannte 7 und 8 nicht.
        {..._toolManifest(), 'format': 1},
        {..._toolManifest(), 'format': 3},
        {..._toolManifest(), 'zoom': 12},
      ]) {
        expect(() => WaysManifest.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });
  });

  group('Stil-Ebenen', () {
    test('MapLibre: erst alle Bänder, dann je Klasse ein Strich, gefiltert nach `k`', () {
      final layers = wayStyleLayers('ways', dashes: true);
      final bands = [for (final c in WayClass.values) if (c.band != null) c];
      expect(layers, hasLength(bands.length + WayClass.values.length));
      expect([for (final l in layers.take(bands.length)) l['id']], [for (final c in bands) 'ways/band-${c.name}']);
      for (final (i, c) in WayClass.values.indexed) {
        final l = layers[bands.length + i];
        expect(l['id'], 'ways/line-${c.name}');
        expect(l['filter'], ['==', ['get', kWaysKey], c.code]);
        expect(l['source-layer'], kWaysLayer);
        expect(l['minzoom'], kWaysZoom);
        expect((l['paint'] as Map)['line-dasharray'], c.dash);
      }
    });

    test('Web: eine durchgezogene Linie je Klasse, kein Strich', () {
      final layers = wayStyleLayers('ways', dashes: false);
      expect(layers, hasLength(WayClass.values.length));
      for (final l in layers) {
        expect((l['paint'] as Map).containsKey('line-dasharray'), isFalse, reason: '${l['id']}');
      }
      // Ohne Strich trägt die Helligkeit: rauer heißt heller, je Wegart.
      for (final kind in WayKind.values) {
        final lum = [
          for (final c in WayClass.values)
            if (c.kind == kind) c.webColor.computeLuminance(),
        ];
        expect(lum, orderedEquals([...lum]..sort()), reason: '$kind');
        final widths = <double>[for (final c in WayClass.values) if (c.kind == kind) c.width];
        final descending = [...widths]..sort((a, b) => b.compareTo(a));
        expect(widths, orderedEquals(descending), reason: '$kind');
      }
    });

    test('die Codes sind die des Werkzeugs', () {
      final tool = File('tool/way_archive.py').readAsStringSync();
      final classes = RegExp(r'^CLASSES = \{(.*?)\}', multiLine: true, dotAll: true).firstMatch(tool)!.group(1)!;
      final codes = {
        for (final m in RegExp(r'(\d+): "(\w+)"').allMatches(classes)) m.group(2)!: int.parse(m.group(1)!),
      };
      String snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
      expect({for (final c in WayClass.values) snake(c.name): c.code}, codes);
    });

    test('jede Breite liegt bei Zoom 15 über der Linie der Basiskarte', () {
      final style = jsonDecode(File(kMapStyleAsset).readAsStringSync()) as Map<String, dynamic>;
      double baseAt15(String id) {
        final layer = (style['layers'] as List).cast<Map<String, dynamic>>().firstWhere((l) => l['id'] == id);
        final w = (layer['paint'] as Map)['line-width'] as List;
        final stops = w.sublist(3);
        return (stops[stops.indexOf(15) + 1] as num).toDouble();
      }

      final base = {WayKind.track: baseAt15('roads_path_track'), WayKind.path: baseAt15('roads_path')};
      for (final c in WayClass.values) {
        expect(c.width, greaterThan(base[c.kind]!), reason: c.name);
      }
    });

    test('nie eine Trail-Farbe', () {
      const g = AppColors.mapGrades;
      const m = AppColors.mapLines;
      final trail = {
        for (final c in [g.s0, g.s1, g.s2, g.s3, g.ungraded, g.uphill, m.mine, m.buddy, m.warning, m.note,
          m.official, m.candidate, m.ride])
          c.toARGB32(),
      };
      for (final c in WayClass.values) {
        for (final color in [c.color, c.webColor, ?c.band]) {
          expect(trail, isNot(contains(color.toARGB32())), reason: c.name);
          // Grau-Braun: keine kräftige Farbe.
          expect(HSLColor.fromColor(color).saturation, lessThan(0.3), reason: c.name);
        }
      }
    });

    test('flutter_map liest das Thema', () {
      expect(wayTheme().layers, hasLength(WayClass.values.length));
    });
  });

  group('Manifest-Provider', () {
    (ProviderContainer, List<int>) make({required bool enabled, required bool offline, Object? error}) {
      final asked = <int>[];
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(FakeSettings(wayLayerEnabled: enabled)),
        noConnectivityProvider.overrideWithValue(offline),
        waysManifestLoaderProvider.overrideWithValue(() async {
          asked.add(1);
          if (error != null) throw error;
          return WaysManifest.fromJson(_toolManifest());
        }),
      ]);
      addTearDown(c.dispose);
      return (c, asked);
    }

    test('an und online: geholt', () async {
      final (c, asked) = make(enabled: true, offline: false);
      expect((await c.read(waysManifestProvider.future))?.file, 'ways-20261101.pmtiles');
      expect(asked, hasLength(1));
    });

    test('aus oder offline: keine Anfrage', () async {
      for (final (enabled, offline) in [(false, false), (true, true)]) {
        final (c, asked) = make(enabled: enabled, offline: offline);
        expect(await c.read(waysManifestProvider.future), isNull);
        expect(asked, isEmpty, reason: 'an=$enabled offline=$offline');
      }
    });

    test('noch kein Bau oder fremdes Format: still null', () async {
      final (c, _) = make(enabled: true, offline: false, error: const FormatException('Format 2'));
      expect(await c.read(waysManifestProvider.future), isNull);
    });

    test('der Schalter merkt sich die Wahl', () async {
      final settings = FakeSettings();
      final c = ProviderContainer(overrides: [settingsProvider.overrideWithValue(settings)]);
      addTearDown(c.dispose);
      expect(c.read(wayLayerEnabledProvider), isTrue, reason: 'ab Werk an');
      c.read(wayLayerEnabledProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(settings.wayLayerEnabled, isFalse);
    });
  });

  test('die Legende zeigt die Wege nur, solange die Ebene an ist', () {
    final on = legendSamples();
    expect([for (final s in on) if (s.way != null) s.way], WayClass.values);
    expect([for (final s in legendSamples(ways: false)) if (s.way != null) s], isEmpty);
    expect(legendGroupTitle(on.firstWhere((s) => s.way == WayClass.trackGood).group), 'Forstweg');
    expect(legendGroupTitle(on.firstWhere((s) => s.way == WayClass.pathEasy).group), 'Pfad');
    final labels = [for (final s in on) s.label];
    expect(labels.toSet(), hasLength(labels.length), reason: 'jede Probe einmal auffindbar');
  });
}
