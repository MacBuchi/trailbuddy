// Gesehene kleine Host-Dateien (#596 H4) in einer ECHTEN IndexedDB —
// läuft nur mit `flutter test --platform chrome` (CI: Schritt „Web-Test
// auf dart2js"). Die Regeln prüft `test/data/seen_host_files_test.dart`
// auf der VM; hier nur, dass Text und Index im Browser zurückkommen und
// dass der Zugang wirklich der Browser ist.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/browser_storage.dart';
import 'package:trailbuddy/data/seen_host_files.dart';

void main() {
  test('Text und Alter kommen nach einem Neustart zurück', () async {
    final factory = browserIdbFactory();
    expect(factory?.persistent, isTrue, reason: 'sonst bewiese grün nichts');
    final at = DateTime.utc(2026, 11, 20, 8);
    await IdbSeenHostFiles(
      factory!,
      now: () => at,
    ).write('pois-20261120/names/ho.json', '{"places":["Hörnle"]}');
    final again = chooseSeenHostFiles(web: true, factory: factory)!;
    final file = await again.read('pois-20261120/names/ho.json');
    expect(file?.text, '{"places":["Hörnle"]}');
    expect(file?.at.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
  });
}
