// Der Gesprächskatalog (#509, Prüfleiter S3, T2): `docs/watch_cases.json`
// → `gespraeche`. Jedes Gespräch spielt hier die Seite des Handys gegen den
// echten WatchSync und WatchRideInbox — die Schritte der Uhr kommen als
// Nachrichten an, die des Handys müssen hinausgehen. Die Seite der Uhr
// spielt `garmin/source/GeneratedTalks.mc` (erzeugt von
// `tool/watch_talks.py`) gegen den Ablaufkern. Die Form steht in
// `gespraeche_form` der Falldatei.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/garmin/watch_ride.dart' show encodeWatchRide;
import 'package:trailbuddy/features/rides/ride_providers.dart' show rideProvider;
import 'package:trailbuddy/features/routing/nav_providers.dart' show navigationProvider;
import 'package:trailbuddy/features/trails/trail_providers.dart' show trailsProvider;

import 'watch_phone.dart';

Map<String, dynamic> _doc() => jsonDecode(File('docs/watch_cases.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _talks() => (_doc()['gespraeche'] as List<dynamic>).cast<Map<String, dynamic>>();

/// Die Arten, die eine Seite sendet und versteht — aus dem Code, nicht aus
/// einer Liste: Eine neue Art ohne Gespräch fällt so auf.
Set<String> _watchTypes() {
  final src = ['WatchCore.mc', 'RideLog.mc'].map((f) => File('garmin/source/$f').readAsStringSync()).join('\n');
  return {
    for (final m in RegExp(r'"t" => "([a-z]+)"').allMatches(src)) m.group(1)!,
    for (final m in RegExp(r'"([a-z]+)"\.equals\(t\)').allMatches(src)) m.group(1)!,
  };
}

Set<String> _phoneTypes() {
  final src = ['watch_route.dart', 'watch_ride.dart']
      .map((f) => File('lib/features/garmin/$f').readAsStringSync())
      .join('\n');
  // Arten sind ein oder zwei Buchstaben; die Fehlercodes (`mem`, `ver` …)
  // sind länger.
  return {for (final m in RegExp(r"const kWatch\w+ = '([a-z]{1,2})';").allMatches(src)) m.group(1)!};
}

void main() {
  test('jede Art Nachricht kommt in einem Gespräch vor', () {
    final talks = _talks();
    expect(talks, isNotEmpty);
    final spoken = {
      for (final g in talks)
        for (final s in (g['schritte'] as List<dynamic>).cast<Map<String, dynamic>>())
          if (s['msg'] case final Map<String, dynamic> m) m['t'] as String,
    };
    final watch = _watchTypes(), phone = _phoneTypes();
    expect(watch, containsAll(['hi', 'ok', 'r', 'w']), reason: 'die Arten der Uhr nicht gelesen');
    expect(phone, containsAll(['hi', 'ok', 'r', 'w']), reason: 'die Arten des Handys nicht gelesen');
    expect(watch.difference(phone), isEmpty, reason: 'die Uhr kennt Arten, die das Handy nicht kennt');
    expect(phone.difference(watch), isEmpty, reason: 'das Handy kennt Arten, die die Uhr nicht kennt');
    expect(watch.difference(spoken), isEmpty, reason: 'über diese Arten redet kein Gespräch');
    expect(spoken.difference(watch), isEmpty, reason: 'ein Gespräch nennt eine Art, die es nicht gibt');

    // Jedes Gespräch, das die Uhr spielt, steht erzeugt in GeneratedTalks.mc.
    final gen = File('garmin/source/GeneratedTalks.mc').readAsStringSync();
    for (final g in talks) {
      final id = g['id'] as String;
      expect(g['schritte'], isNotEmpty, reason: '$id ohne Schritte');
      if (g['nur'] == 'handy') {
        expect(g['warum_nur'], isA<String>(), reason: '$id: warum nur eine Seite?');
        continue;
      }
      expect(gen, contains('function ${talkFunction(id)}('), reason: '$id fehlt in GeneratedTalks.mc');
    }
  });

  for (final g in _talks()) {
    if (g['nur'] == 'uhr') continue;
    testWidgets('Gespräch ${g['id']}: ${g['titel']}', (tester) async {
      await _PhoneSide(tester, g).play();
    });
  }
}

/// Der Name der erzeugten Monkey-C-Funktion (wie `tool/watch_talks.py`).
String talkFunction(String id) => 'talk_${id.replaceAll('-', '_')}';

class _PhoneSide {
  _PhoneSide(this.tester, this.talk);

  final WidgetTester tester;
  final Map<String, dynamic> talk;
  late final WatchPhone phone;

  /// Was `$name` heißt, sobald eine Seite es festgelegt hat.
  final vars = <String, Object>{};

  /// Bis hierher ist das Gesendete abgehakt.
  int cursor = 0;

  Future<void> pump([Duration d = Duration.zero]) => tester.pump(d);

  Future<void> play() async {
    final setup = (talk['handy'] as List<dynamic>).cast<String>();
    phone = WatchPhone(
      trails: setup.contains('frei') ? [freeTrail()] : const [],
      jumped: setup.contains('sprung'),
    );
    phone.fix.next = ridePointAt(1700000000);
    await phone.open();
    if (setup.contains('frei')) {
      // Die Trails laden über echte Ein- und Ausgabe: Unter der falschen
      // Zeit von testWidgets wird das nie fertig.
      await tester.runAsync(() => phone.c.read(trailsProvider.future).timeout(const Duration(seconds: 20)));
    }
    await pump();
    final steps = (talk['schritte'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < steps.length; i++) {
      await _step(i + 1, steps[i]);
    }
    phone.c.dispose();
    await pump(const Duration(minutes: 5));
  }

  Future<void> _step(int n, Map<String, dynamic> s) async {
    final where = '${talk['id']} Schritt $n';
    final msg = (s['msg'] as Map<String, dynamic>?)?.cast<String, Object>();
    final gleich = (s['gleich'] as List<dynamic>? ?? const []).cast<String>();
    final wait = Duration(milliseconds: s['nach_ms'] as int? ?? 0);
    if (s['von'] == 'handy') {
      switch (s['tu']) {
        case null:
          break;
        case 'navigation':
          phone.navigate();
        case 'beenden':
          phone.endNavigation();
        case final other:
          fail('$where: unbekannte Handlung am Handy „$other“');
      }
      if (s['still'] == true) {
        final before = phone.sent.length;
        await pump(wait);
        expect(phone.sent.sublist(before).map((m) => m['t']), isEmpty, reason: '$where: das Handy sollte still sein');
      } else if (msg != null) {
        await _expectSent(where, msg, gleich);
        await pump(wait);
      } else {
        await pump(wait);
      }
    } else {
      // Die Uhr spricht: Ihre Handlung sieht das Handy nicht, nur die
      // Nachricht — und die nur, wenn sie ankommt.
      if (msg != null && s['verloren'] != true) phone.bridge.answer(_resolve(msg));
      for (var k = 0; k < 5; k++) {
        await pump();
      }
      await pump(wait);
    }
    final dann = s['dann'] as Map<String, dynamic>?;
    for (final st in _list(dann?['handy'])) {
      _expectState(where, st);
    }
  }

  static List<String> _list(Object? v) => v == null ? const [] : (v is List ? v.cast<String>() : [v as String]);

  /// Die Nachricht der Uhr, wie sie beim Handy ankommt: `$name` eingesetzt,
  /// eine Fahrt mit `c: "*"` erfunden.
  Map<String, Object> _resolve(Map<String, Object> msg) {
    Object res(Object v) => switch (v) {
          final String s when s.startsWith(r'$') => vars[s.substring(1)] ?? s.substring(1),
          final List<dynamic> l => [for (final e in l) res(e as Object)],
          _ => v,
        };
    final out = {for (final e in msg.entries) e.key: res(e.value)};
    if (out['t'] == 'w' && out['c'] == '*') out['c'] = encodeWatchRide(watchRidePoints(40));
    return out;
  }

  /// Das Handy muss [msg] senden — gesucht ab [cursor], höchstens zwei
  /// Minuten der Testuhr. `r` heißt: alle Stücke einer Route.
  Future<void> _expectSent(String where, Map<String, Object> msg, List<String> gleich) async {
    final t = msg['t'];
    for (var waited = 0;; waited += 100) {
      final sent = phone.sent;
      for (var i = cursor; i < sent.length; i++) {
        final m = sent[i];
        if (m['t'] != t || !_placeholdersFit(m, msg)) continue;
        for (final key in msg.keys) {
          expect(m.containsKey(key), isTrue, reason: '$where: `$t` ohne Schlüssel `$key` — $m');
        }
        for (final key in gleich) {
          expect(m[key], msg[key], reason: '$where: `$t.$key`');
        }
        _bind(m, msg);
        cursor = i + 1;
        if (t == 'r') await _restOfRoute(where, m);
        return;
      }
      if (waited >= 120000) {
        fail('$where: das Handy sendete kein `$t` ${_resolve(msg)} — gesendet: '
            '${sent.sublist(cursor).map((m) => m['t']).toList()}');
      }
      await pump(const Duration(milliseconds: 100));
    }
  }

  /// Die übrigen Stücke der Route [first] (`p` 0 … `n`-1).
  Future<void> _restOfRoute(String where, Map<String, Object> first) async {
    final id = first['id'], n = first['n'] as int;
    expect(first['p'], 0, reason: '$where: die Route beginnt nicht mit Stück 0');
    for (var p = 1; p < n; p++) {
      final sent = phone.sent;
      final i = sent.indexWhere((m) => m['t'] == 'r' && m['id'] == id && m['p'] == p, cursor);
      expect(i, isNot(-1), reason: '$where: Stück $p von $n fehlt');
      cursor = i + 1;
    }
  }

  bool _placeholdersFit(Map<String, Object> sent, Map<String, Object> msg) {
    for (final e in msg.entries) {
      final v = e.value;
      if (v is String && v.startsWith(r'$')) {
        final bound = vars[v.substring(1)];
        if (bound != null && sent[e.key] != bound) return false;
      }
    }
    return true;
  }

  void _bind(Map<String, Object> sent, Map<String, Object> msg) {
    for (final e in msg.entries) {
      final v = e.value;
      if (v is String && v.startsWith(r'$') && sent[e.key] != null) vars.putIfAbsent(v.substring(1), () => sent[e.key]!);
    }
  }

  void _expectState(String where, String st) {
    final sync = phone.sync;
    final ride = phone.c.read(rideProvider);
    final nav = phone.c.read(navigationProvider);
    final phases = {
      'idle': WatchSyncPhase.idle,
      'sendet': WatchSyncPhase.sending,
      'gefragt': WatchSyncPhase.prompted,
      'gesendet': WatchSyncPhase.sent,
      'gespeichert': WatchSyncPhase.stored,
      'unbestaetigt': WatchSyncPhase.unconfirmed,
      'fehler': WatchSyncPhase.failed,
    };
    final why = '$where: Stand „$st“ am Handy';
    if (phases[st] case final phase?) {
      expect(sync.phase, phase, reason: why);
    } else if (st.startsWith('fehler:')) {
      expect((sync.phase, sync.error), (WatchSyncPhase.failed, st.substring(7)), reason: why);
    } else if (st == 'nav_an') {
      expect(nav, isNotNull, reason: why);
    } else if (st == 'nav_aus') {
      expect(nav, isNull, reason: why);
    } else if (st == 'nimmt_auf') {
      expect(ride, isNotNull, reason: why);
    } else if (st == 'aus') {
      expect(ride, isNull, reason: why);
    } else if (st.startsWith('marken:')) {
      expect(ride?.marks.length, int.parse(st.substring(7)), reason: why);
    } else {
      fail('$where: unbekannter Stand am Handy „$st“');
    }
  }
}
