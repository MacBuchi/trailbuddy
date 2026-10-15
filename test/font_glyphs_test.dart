import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';

/// Die Codepunkte einer TrueType-Datei aus ihrer `cmap` (Format 4 und 12).
Set<int> _codepoints(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  final tables = b.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes(
            List.generate(4, (k) => b.getUint8(rec + k))) ==
        'cmap') {
      cmap = b.getUint32(rec + 8);
    }
  }
  expect(cmap, isNot(-1), reason: '$path ohne cmap');
  final out = <int>{};
  final subtables = b.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final sub = cmap + b.getUint32(cmap + 4 + i * 8 + 4);
    switch (b.getUint16(sub)) {
      case 4:
        final segX2 = b.getUint16(sub + 6);
        final ends = sub + 14;
        final starts = ends + segX2 + 2;
        final deltas = starts + segX2;
        final offsets = deltas + segX2;
        for (var s = 0; s < segX2; s += 2) {
          final start = b.getUint16(starts + s);
          final end = b.getUint16(ends + s);
          final delta = b.getUint16(deltas + s);
          final ro = b.getUint16(offsets + s);
          for (var c = start; c <= end && c != 0xFFFF; c++) {
            final glyph = ro == 0
                ? (c + delta) & 0xFFFF
                : b.getUint16(offsets + s + ro + 2 * (c - start));
            if (glyph != 0) out.add(c);
          }
        }
      case 12:
        final groups = b.getUint32(sub + 12);
        for (var g = 0; g < groups; g++) {
          final rec = sub + 16 + g * 12;
          for (var c = b.getUint32(rec); c <= b.getUint32(rec + 4); c++) {
            out.add(c);
          }
        }
    }
  }
  return out;
}

void main() {
  // #338: Barlow hat keine Pfeile. Was sie nicht hat, muss die gebündelte
  // Ersatzschrift haben — sonst holt Flutter Web eine aus dem Netz, und
  // offline stehen leere Kästchen da.
  test('jedes Zeichen der Texte steht in Barlow oder JetBrains Mono', () {
    final barlow = _codepoints('assets/fonts/Barlow-Regular.ttf');
    final mono = _codepoints('assets/fonts/JetBrainsMono-Medium.ttf');
    expect(barlow, contains('a'.codeUnitAt(0)));
    expect(mono, contains(0x2193), reason: 'die Ersatzschrift für ↓');

    final missing = <String>{};
    for (final f in Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))) {
      final arb = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final e in arb.entries) {
        if (e.key.startsWith('@') || e.value is! String) continue;
        for (final c in (e.value as String).runes) {
          if (c < 0x20 || barlow.contains(c) || mono.contains(c)) continue;
          missing.add('${e.key}: ${String.fromCharCode(c)} '
              '(U+${c.toRadixString(16).toUpperCase()})');
        }
      }
    }
    expect(missing, isEmpty);
  });

  test('das Theme reicht JetBrains Mono als Ersatz an alle Stile weiter', () {
    for (final p in [AppColors.light, AppColors.dark]) {
      final t = buildAppTheme(p).textTheme;
      for (final s in [
        t.bodyMedium,
        t.bodySmall,
        t.titleMedium,
        t.titleLarge,
        t.labelLarge,
        AppFonts.numbers(t.bodySmall),
      ]) {
        expect(s?.fontFamilyFallback, contains(AppFonts.mono));
      }
    }
  });

  testWidgets('ein Text ohne eigenen Stil erbt den Ersatz', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppColors.light),
      home: Scaffold(
        body: Builder(builder: (context) {
          style = DefaultTextStyle.of(context).style;
          return const Text('↓ 32 Hm');
        }),
      ),
    ));
    expect(style.fontFamilyFallback, contains(AppFonts.mono));
  });
}
