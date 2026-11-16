// Das Abbild der Uhr-Ansicht (#511, S4): andere Größen und lange Texte in
// CI. Je Gerät und Sprache ein Bogen mit allen Bildern (Golden,
// bildpunktgenau), je Gerät ein Bericht, was nicht passt
// (`watch_twin/<gerät>.txt`). Der Bericht ist ein Golden: Ein neuer
// Befund ist rot, ein behobener auch (dann nachziehen). Was heute drin
// steht, ist gesammelt — für 240 px (Manifest) in #555, für andere
// Größen als Aufgabe einer Portierung.
//
// Nachziehen: flutter test --update-goldens test/garmin/watch_twin_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'watch_twin.dart';

const _dir = 'test/garmin/watch_twin';
const _langs = ['deu', 'eng'];
const _cols = 7;
const _gap = 6;

Set<String> _manifestDevices() {
  final xml = File('garmin/manifest.xml').readAsStringSync();
  return {for (final m in RegExp(r'product id="(\w+)"').allMatches(xml)) m.group(1)!};
}

/// Alle Bilder eines Geräts und einer Sprache, dazu ihre Befunde.
({img.Image sheet, List<String> problems}) _render(WatchDevice d, String lang) {
  final w = d.screen;
  final rows = (kTwinScenes.length + _cols - 1) ~/ _cols;
  final sheet = img.Image(width: _cols * (w + _gap) + _gap, height: rows * (w + _gap) + _gap);
  img.fill(sheet, color: img.ColorRgb8(0x30, 0x30, 0x30));
  final problems = <String>[];
  for (var i = 0; i < kTwinScenes.length; i++) {
    final sc = kTwinScenes[i];
    final twin = WatchTwin(d, lang)..draw(sc);
    img.compositeImage(sheet, twin.canvas.toImage(),
        dstX: _gap + (i % _cols) * (w + _gap), dstY: _gap + (i ~/ _cols) * (w + _gap));
    for (final p in twin.problems()) {
      problems.add('$lang ${sc.name}: $p');
    }
  }
  return (sheet: sheet, problems: problems);
}

int _diff(img.Image a, img.Image b) {
  if (a.width != b.width || a.height != b.height) return -1;
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.getPixel(x, y);
      final q = b.getPixel(x, y);
      if (p.r != q.r || p.g != q.g || p.b != q.b) n++;
    }
  }
  return n;
}

void main() {
  test('jede Marke in garmin/source trägt den Wert aus watch_layout.json', () {
    // Dasselbe prüft `tool/watch_layout.py --check` — hier, damit ein
    // vergessener Lauf des Skripts auch im Test rot ist.
    final j = WatchLayout.raw();
    const fonts = {
      'xtiny': 'Graphics.FONT_XTINY',
      'tiny': 'Graphics.FONT_TINY',
      'small': 'Graphics.FONT_SMALL',
      'medium': 'Graphics.FONT_MEDIUM',
      'large': 'Graphics.FONT_LARGE',
      'numberMedium': 'Graphics.FONT_NUMBER_MEDIUM',
    };
    final values = j['values'] as Map<String, dynamic>;
    final names = (j['fonts'] as Map<String, dynamic>).cast<String, String>();
    final seen = <String>{};
    for (final file in (j['files'] as List).cast<String>()) {
      final src = File(file).readAsStringSync();
      for (final m in RegExp(r'/\*([LF]):(\w+)\*/\s*(-?\d+|Graphics\.FONT_\w+)').allMatches(src)) {
        final kind = m.group(1)!;
        final name = m.group(2)!;
        seen.add('$kind:$name');
        final want = kind == 'L' ? '${(values[name] as Map?)?['v']}' : fonts[names[name]];
        expect(m.group(3), want, reason: '$file $kind:$name — python3 tool/watch_layout.py');
      }
    }
    expect(seen, {...values.keys.map((k) => 'L:$k'), ...names.keys.map((k) => 'F:$k')});
  });

  test('jedes Zeichen liegt in seiner Box (#558) und ist in der Liste', () {
    final sy = WatchLayout.raw()['symbols'] as Map<String, dynamic>;
    final defs = sy['def'] as Map<String, dynamic>;
    expect((sy['list'] as List).toSet(), defs.keys.toSet());
    defs.forEach((name, v) {
      final d = v as Map<String, dynamic>;
      final w = d['w'] as int;
      expect(d['h'], 16, reason: name);
      for (final op in (d['ops'] as List<dynamic>).cast<List<dynamic>>()) {
        final a = op.skip(2).cast<int>().toList();
        final pts = <List<int>>[];
        switch (op[0]) {
          case 'p':
            for (var k = 0; k < a.length; k += 2) {
              pts.add([a[k], a[k + 1]]);
            }
          case 'r':
            pts..add([a[0], a[1]])..add([a[0] + a[2], a[1] + a[3]]);
          case 'c':
          case 'o':
            // Kreis: Mitte ± Radius (bei Ring ± halbe Strichbreite)
            final r = a[2] + (op[0] == 'o' ? a[3] ~/ 2 : 0);
            pts..add([a[0] - r, a[1] - r])..add([a[0] + r, a[1] + r]);
          case 'l':
            // Die Enden zählen, die Kappen der Strichbreite nicht.
            pts..add([a[0], a[1]])..add([a[2], a[3]]);
        }
        for (final p in pts) {
          expect(p[0], inInclusiveRange(0, w), reason: '$name x ${p[0]}');
          expect(p[1], inInclusiveRange(0, 16), reason: '$name y ${p[1]}');
        }
      }
    });
  });

  test('jedes Gerät des Abbilds ist gemessen, die Uhren des Manifests mit 240 px', () {
    final manifest = _manifestDevices();
    for (final id in WatchDevice.all()) {
      final d = WatchDevice.load(id);
      expect(d.fonts.keys, containsAll(['xtiny', 'tiny', 'small', 'large', 'numberMedium']), reason: id);
      if (manifest.contains(id)) expect(d.screen, 240, reason: id);
    }
    // Wer eine Uhr anderer Größe ins Manifest nimmt, braucht Layoutwerte
    // je Größe im Monkey-C-Bau (heute nur 240, garmin/CLAUDE.md).
    expect(WatchDevice.all().where(manifest.contains), isNotEmpty);
  });

  test('ein Wert in watch_layout.json verschiebt, was das Abbild zeichnet', () {
    final d = WatchDevice.load('fenix5');
    final a = WatchTwin(d, 'deu')..draw(kTwinScenes.firstWhere((s) => s.name == 'anfahrt'));
    final y = a.boxes.firstWhere((b) => b.id == 'field_name').y0;
    expect(y, 160 + 2 + 26 - 21 + 1, reason: 'field_y + field_line1_dy + Höhe − Ascent + 1');
    expect(WatchLayout.forSize(260).v('field_y'), (160 * 260 / 240).round());
    expect(WatchLayout.forSize(260).v('ring_w'), 8, reason: 'fixed');
  });

  for (final id in WatchDevice.all()) {
    group(id, () {
      final d = WatchDevice.load(id);
      final problems = <String>[];
      for (final lang in _langs) {
        test('Bogen $lang', () {
          final r = _render(d, lang);
          problems.addAll(r.problems);
          final file = File('$_dir/${id}_$lang.png');
          if (autoUpdateGoldenFiles || !file.existsSync()) {
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(img.encodePng(r.sheet));
            if (!autoUpdateGoldenFiles) fail('${file.path} neu geschrieben — ansehen und committen');
            return;
          }
          final want = img.decodePng(file.readAsBytesSync())!;
          final n = _diff(r.sheet, want);
          if (n != 0) {
            final out = File('build/watch_twin/${id}_$lang.png')..parent.createSync(recursive: true);
            out.writeAsBytesSync(img.encodePng(r.sheet));
            fail('${file.path}: ${n < 0 ? 'andere Größe' : '$n Bildpunkte anders'} — neu: ${out.path}; '
                'gewollt? flutter test --update-goldens test/garmin/watch_twin_test.dart');
          }
        });
      }
      test('Befunde', () {
        final file = File('$_dir/$id.txt');
        final text = problems.isEmpty ? '' : '${problems.join('\n')}\n';
        if (autoUpdateGoldenFiles) {
          file.writeAsStringSync(text);
          return;
        }
        final want = file.existsSync() ? file.readAsStringSync() : '';
        expect(const LineSplitter().convert(text), const LineSplitter().convert(want),
            reason: '${file.path}: neue oder verschwundene Befunde — gewollt? --update-goldens');
      });
    });
  }
}
