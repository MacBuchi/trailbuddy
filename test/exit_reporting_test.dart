// Der Weg von Androids Beendigungs-Historie in `error_reports` (#40, PilzBuddy #147).
//
// Ohne diesen Weg hinterlässt ein ANR oder Absturz gar nichts: `logError`
// sieht nur, was die App überlebt. Genau deshalb blieb PilzBuddys #142 unsichtbar, bis
// jemand ein USB-Kabel angesteckt hat.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/data/error_report_repository.dart';
import 'package:trailbuddy/data/exit_info_repository.dart';
import 'package:trailbuddy/data/exit_reporting.dart';

/// Ein geschriebener Bericht — geprüft wird der Inhalt, nicht der Aufruf.
class ReportedExit {
  ReportedExit(this.reason, this.summary, this.when, this.trace);

  final String reason;
  final String summary;
  final DateTime when;
  final String? trace;
}

/// Sammelt statt zu schreiben; ohne Netz, wie der Rest der Suite.
class FakeErrorReports implements ErrorReportRepository {
  final exits = <ReportedExit>[];

  @override
  Future<void> reportExit({
    required String reason,
    required String summary,
    required DateTime when,
    String? trace,
  }) async => exits.add(ReportedExit(reason, summary, when, trace));

  @override
  Future<void> report(
    String context,
    Object error,
    StackTrace? stackTrace,
  ) async {}
}

/// Liefert vorgegebene Einträge, statt die Plattform zu fragen.
class _FakeExits implements ExitInfoRepository {
  _FakeExits(this.exits, {this.trace, this.throwOnRead = false});

  final List<AppExit> exits;
  final String? trace;
  final bool throwOnRead;
  int traceCalls = 0;

  @override
  Future<List<AppExit>> recentExits({int limit = 10}) async {
    if (throwOnRead) throw StateError('Kanal fehlt');
    return exits;
  }

  @override
  Future<String?> traceFor(AppExit exit) async {
    traceCalls++;
    return exit.hasTrace ? trace : null;
  }
}

AppExit _exit(
  String reason,
  DateTime when, {
  int rssKb = 0,
  bool hasTrace = false,
}) => AppExit(
  timestamp: when,
  reason: reason,
  description: 'beschreibung',
  rssKb: rssKb,
  hasTrace: hasTrace,
);

void main() {
  // Für den MethodChannel-Mock im letzten Block (#394).
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  ExitReporter reporter(FakeErrorReports reports, _FakeExits exits) =>
      ExitReporter(
        exits: exits,
        reports: reports,
        directory: () async => tempDir,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trailbuddy_exit_test');
  });
  tearDown(() async {
    setErrorSink(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('Ein ANR wird gemeldet, mit Zeitpunkt und Thread-Dump', () async {
    final when = DateTime(2026, 7, 26, 15, 39);
    final reports = FakeErrorReports();
    final exits = _FakeExits([
      _exit('ANR', when, rssKb: 1900 * 1024, hasTrace: true),
    ], trace: '"main" prio=5 tid=1 Native');

    await reporter(reports, exits).reportPending();

    expect(reports.exits, hasLength(1));
    final report = reports.exits.single;
    expect(report.reason, 'ANR');
    expect(
      report.when,
      when,
      reason:
          'Der Todeszeitpunkt, nicht der Meldezeitpunkt — sonst landet '
          'ein Absturz von Freitagnacht im Digest der Folgewoche.',
    );
    expect(report.trace, contains('"main"'));
    expect(
      report.summary,
      contains('RSS 1900 MB'),
      reason: 'Bei #142 zeigte der RSS die Ursache vor jedem Stacktrace.',
    );
  });

  test('Ein normales Beenden wird NICHT gemeldet', () async {
    // Sonst füllt jedes Wegwischen aus der Übersicht den Wochendigest —
    // dieselbe Lehre wie #124 und #136.
    final reports = FakeErrorReports();
    final exits = _FakeExits([
      _exit('USER_REQUESTED', DateTime(2026, 7, 26, 12)),
      _exit('EXIT_SELF', DateTime(2026, 7, 26, 13)),
      _exit('OTHER', DateTime(2026, 7, 26, 14)),
    ]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits, isEmpty);
  });

  test(
    'Derselbe Eintrag wird beim zweiten Start nicht erneut gemeldet',
    () async {
      final reports = FakeErrorReports();
      final exits = _FakeExits([_exit('CRASH', DateTime(2026, 7, 26, 15))]);

      await reporter(reports, exits).reportPending();
      await reporter(reports, exits).reportPending();

      expect(reports.exits, hasLength(1));
    },
  );

  test('Nur Einträge nach dem letzten gemeldeten kommen dazu', () async {
    final reports = FakeErrorReports();
    final alt = _exit('ANR', DateTime(2026, 7, 26, 10));
    final neu = _exit('ANR', DateTime(2026, 7, 26, 20));

    await reporter(reports, _FakeExits([alt])).reportPending();
    await reporter(reports, _FakeExits([alt, neu])).reportPending();

    expect(reports.exits.map((e) => e.when), [alt.timestamp, neu.timestamp]);
  });

  test('Auch ohne meldbare Einträge rückt der Merker vor', () async {
    // Sonst wird die Historie bei jedem Start erneut durchgesehen.
    final reports = FakeErrorReports();
    final harmlos = _exit('USER_REQUESTED', DateTime(2026, 7, 26, 18));
    await reporter(reports, _FakeExits([harmlos])).reportPending();

    // Ein ANR VOR dem harmlosen Eintrag gilt damit als erledigt.
    final alt = _exit('ANR', DateTime(2026, 7, 26, 9));
    await reporter(reports, _FakeExits([harmlos, alt])).reportPending();

    expect(reports.exits, isEmpty);
  });

  test('Ein kaputter Kanal bricht den Start nicht ab', () async {
    // Diagnose, die den Start gefährdet, ist schlimmer als keine.
    final gemeldet = <String>[];
    setErrorSink((context, _, _) => gemeldet.add(context));
    final reports = FakeErrorReports();

    await expectLater(
      reporter(
        reports,
        _FakeExits(const [], throwOnRead: true),
      ).reportPending(),
      completes,
    );
    expect(reports.exits, isEmpty);
    expect(gemeldet, ['Beendigungsgrund melden']);
  });

  test('Ohne ANR wird kein Thread-Dump angefordert', () async {
    // Das Lesen des Dumps ist teuer (Rohdatei ~1,8 MB).
    final reports = FakeErrorReports();
    final exits = _FakeExits([_exit('LOW_MEMORY', DateTime(2026, 7, 26, 15))]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits.single.trace, isNull);
  });

  // Die Speicherzahlen im Bericht — die Stelle, an der die Auswertung von
  // #151 in die Irre lief: Dort stand „RSS 0 MB · PSS 0 MB", während
  // `dumpsys` für denselben Prozess 1,7–1,9 GB zeigte. Der Speicher schied
  // damit als Ursache aus, ohne je gemessen worden zu sein.
  group('AppExit.summary', () {
    AppExit exitWith({int rssKb = 0, int pssKb = 0}) => AppExit(
      timestamp: DateTime(2026, 7, 26, 22, 25),
      reason: 'ANR',
      rssKb: rssKb,
      pssKb: pssKb,
      importance: 100,
    );

    test(
      'Der Kanal liefert kB, der Bericht zeigt MB — genau einmal geteilt',
      () {
        // Androids getRss()/getPss() liefern kB. Diese eine Umrechnung ist
        // die einzige, die es geben darf: MainActivity.kt teilte vorher
        // schon einmal, und aus 1,9 GB wurden dadurch „2 MB".
        final exit = exitWith(rssKb: 1900 * 1024, pssKb: 1000 * 1024);
        expect(exit.summary, contains('RSS 1900 MB'));
        expect(exit.summary, contains('PSS 1000 MB'));
      },
    );

    test('Nicht gemessen ist etwas anderes als null Megabyte', () {
      // Stirbt der Prozess, bevor das System eine Stichprobe nimmt, sind
      // beide Werte 0 (so dokumentiert). „0 MB" liest sich wie eine
      // Messung und ist keine.
      final exit = exitWith();
      expect(exit.summary, contains('RSS unbekannt'));
      expect(exit.summary, contains('PSS unbekannt'));
      expect(exit.summary, isNot(contains('0 MB')));
    });

    test('fromMap skaliert nichts — was der Kanal schickt, sind kB', () {
      final exit = AppExit.fromMap({
        'timestamp': DateTime(2026, 7, 26, 22, 25).millisecondsSinceEpoch,
        'reasonName': 'ANR',
        'rssKb': 1900 * 1024,
        'pssKb': 1000 * 1024,
      })!;
      expect(exit.rssKb, 1900 * 1024);
      expect(exit.pssKb, 1000 * 1024);
    });
  });

  group('traceFor über den echten Kanal (#394)', () {
    // Die Fake oben ersetzt `ExitInfoRepository` ganz — die Verzweigung
    // „Text oder Tombstone" liegt darunter und wäre sonst ungeprüft.
    const channel = MethodChannel('de.mcbuchi.trailbuddy/exit_info');
    late Object? answer;
    var calls = 0;

    setUp(() {
      calls = 0;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return answer;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    AppExit exitWith(String reason, {bool hasTrace = true}) => AppExit(
      timestamp: DateTime.utc(2026, 9, 7),
      reason: reason,
      hasTrace: hasTrace,
    );

    test('ein ANR kommt als Text und geht unverändert durch', () async {
      answer = '"main" prio=5 tid=1 Native';
      final trace = await ExitInfoRepository().traceFor(exitWith('ANR'));
      expect(trace, '"main" prio=5 tid=1 Native');
    });

    test('ein nativer Absturz kommt als Bytes und wird gelesen', () async {
      // Genau der Fall aus #376: CRASH_NATIVE, und bis 1.121.0 kam er
      // ohne eine Zeile Spur an, obwohl Android das Tombstone bereithielt.
      answer = _tombstoneBytes();
      final trace = await ExitInfoRepository().traceFor(
        exitWith('CRASH_NATIVE'),
      );
      expect(trace, contains('signal 11 (SIGSEGV)'));
      expect(trace, contains('libc.so'));
    });

    test('etwas Drittes ergibt null statt einer Ausnahme', () async {
      // Ein alter Build auf einem neuen Gerät oder umgekehrt.
      answer = 42;
      expect(
        await ExitInfoRepository().traceFor(exitWith('CRASH_NATIVE')),
        isNull,
      );
    });

    test('ohne Dump wird der Kanal gar nicht erst gefragt', () async {
      answer = 'sollte niemand sehen';
      final trace = await ExitInfoRepository().traceFor(
        exitWith('LOW_MEMORY', hasTrace: false),
      );
      expect(trace, isNull);
      expect(calls, 0, reason: 'ein Aufruf je Eintrag beim Start ist genug');
    });
  });
}

/// Ein winziges Tombstone: tid 1, SIGSEGV, ein Frame in libc.
Uint8List _tombstoneBytes() {
  List<int> varint(int v) {
    final out = <int>[];
    var x = v;
    while (x >= 0x80) {
      out.add((x & 0x7f) | 0x80);
      x >>= 7;
    }
    return out..add(x);
  }

  List<int> field(int number, List<int> value) => [
    ...varint((number << 3) | 2),
    ...varint(value.length),
    ...value,
  ];

  final signal = [
    ...varint(1 << 3), ...varint(11), // number
    ...field(2, 'SIGSEGV'.codeUnits), // name
  ];
  final frame = [
    ...varint(1 << 3), ...varint(0xabc), // rel_pc
    ...field(6, '/system/lib64/libc.so'.codeUnits), // file_name
  ];
  final thread = [...field(4, frame)];
  return Uint8List.fromList([
    ...varint(6 << 3), ...varint(1), // tid
    ...field(10, signal),
    ...field(16, [...varint(1 << 3), ...varint(1), ...field(2, thread)]),
  ]);
}
