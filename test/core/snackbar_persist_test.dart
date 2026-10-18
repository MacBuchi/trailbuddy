// Seit Flutter 3.47 bleibt eine SnackBar mit `action` stehen, bis man sie
// wegwischt (`persist ?? action != null`). Auf dem Pixel stand „Planer
// geschlossen · Rückgängig" minutenlang über „Navigation starten" (#371).
// Jede Leiste mit Aktion sagt deshalb ausdrücklich, ob sie bleibt.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Die Argumente jedes `SnackBar(`-Aufrufs in [source], per Klammerzählung
/// (Strings mit Klammern kommen in diesen Aufrufen nicht vor).
Iterable<String> snackBarCalls(String source) sync* {
  for (final m in RegExp(r'\bSnackBar\(').allMatches(source)) {
    var depth = 1, i = m.end;
    while (i < source.length && depth > 0) {
      final c = source[i++];
      if (c == '(') depth++;
      if (c == ')') depth--;
    }
    yield source.substring(m.end, i - 1);
  }
}

void main() {
  test('jede SnackBar mit Aktion setzt persist ausdrücklich', () {
    final offenders = <String>[];
    var withAction = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final call in snackBarCalls(f.readAsStringSync())) {
        if (!call.contains('SnackBarAction(')) continue;
        withAction++;
        if (!RegExp(r'\bpersist:').hasMatch(call)) offenders.add('${f.path}: ${call.split('\n').first.trim()}');
      }
    }
    expect(withAction, greaterThanOrEqualTo(6), reason: 'der Scan findet die bekannten Stellen');
    expect(offenders, isEmpty, reason: 'Flutter 3.47: Aktion ohne persist bleibt für immer stehen');
  });

  testWidgets('eine Leiste mit Aktion und persist: false geht nach ihrer Dauer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Planer geschlossen'),
              action: SnackBarAction(label: 'Rückgängig', onPressed: () {}),
              persist: false,
            )),
            child: const Text('zeigen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('zeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Planer geschlossen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Planer geschlossen'), findsNothing);
  });
}
