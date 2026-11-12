import 'dart:async';

import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart' show kWatchProtocol;

/// Der Weg über Garmin Connect, wie er gemessen ist (#509, Prüfleiter S3):
/// Laufzeit je Nachricht, eine geschlossene Uhr-App, die still verwirft,
/// verlorene Nachrichten, ein Abbruch mitten in den Stücken. Ab Werk aus —
/// ohne Kanal antwortet die Fake-Uhr sofort und verliert nichts.
class WatchChannel {
  WatchChannel({
    this.small = const Duration(milliseconds: 3500),
    this.part = const Duration(milliseconds: 14500),
    this.appOpen = true,
  });

  /// Eine kleine Nachricht braucht 3,5 s, ein Stück der Route (~4 KB)
  /// 14,5 s (gemessen 2026-11-05/06, Konzept-Garmin 8.2).
  final Duration small, part;

  /// Läuft die Uhr-App? Zu meldet Garmin Connect trotzdem `SUCCESS`, und
  /// die Nachricht ist weg (gemessen 2026-11-04).
  bool appOpen;

  /// Die laufenden Nummern (über alles Gesendete, ab 0), die unterwegs
  /// verloren gehen — gesendet ja, angekommen nicht.
  final lose = <int>{};

  /// Die nächste Übertragung von Routenstücken bricht nach so vielen
  /// Nachrichten mit `FAILURE_DURING_TRANSFER` ab.
  int? failRouteAfter;

  Duration delayOf(Map<String, Object> m) => m['t'] == 'r' ? part : small;
}

/// Die Garmin-Uhr im Test (Konzept-Garmin 3): ab Werk keine — wie ein
/// Telefon ohne Garmin Connect. Mit [status] eine verbundene Uhr; was
/// gesendet wird, liegt in [sent], [answer] spielt die Antwort der Uhr.
/// Mit [channel] laufen die Nachrichten so lange wie gemessen; was die
/// Uhr-App erreicht, liegt in [delivered], und [fromWatch] braucht auf dem
/// Rückweg genauso lange.
class FakeGarminBridge implements GarminBridge {
  FakeGarminBridge({this.status_ = WatchStatus.none, this.result = const WatchSendResult('SUCCESS', 0)});

  /// Eine verbundene fēnix 5 mit unserer App.
  FakeGarminBridge.connected(
      {String device = 'fēnix 5', this.result = const WatchSendResult('SUCCESS', 0), this.channel, this.now})
      : status_ = WatchStatus(connect: true, device: device, app: WatchApp.installed);

  /// Der gemessene Kanal, oder null: sofort und verlustfrei.
  WatchChannel? channel;

  /// Die Uhr des Tests für [delivered] (unter `testWidgets` die falsche Zeit).
  DateTime Function()? now;

  /// Was die Uhr-App erreichte, mit der Ankunftszeit.
  final delivered = <({DateTime at, Map<String, Object> msg})>[];

  /// Das SDK sendet der Reihe nach (GarminBridge.kt): eine Übertragung
  /// wartet auf die vorige.
  Future<void> _line = Future.value();
  int _seq = 0;

  /// Je Kennung die angekommenen Stücke — für [autoStore] mit Kanal.
  final _arrived = <String, Set<int>>{};

  WatchStatus status_;
  WatchSendResult result;
  final sent = <List<Map<String, Object>>>[];
  final _messages = StreamController<Object?>.broadcast();
  final _connected = StreamController<void>.broadcast();

  /// Was `openApplication` sagt: ab Werk läuft die Uhr-App schon.
  WatchOpen openResult = WatchOpen.running;

  /// So oft wurde die Uhr-App angestoßen.
  int opens = 0;

  /// Antwortet die Uhr gleich auf jedes vollständige Senden der Route?
  bool autoStore = false;

  /// Eine Plattform ohne Uhr (A9, Web): das SDK fehlt, niemand fragt.
  bool unsupported = false;

  @override
  bool get supported => !unsupported;

  /// Hält `status` an, bis der Test es freigibt (das SDK startet langsam).
  Completer<void>? statusGate;

  @override
  Future<WatchStatus> status() async {
    await statusGate?.future;
    return status_;
  }

  /// Hält jedes Senden der Route an, bis der Test es freigibt — die
  /// Übertragung „läuft" so lange.
  Completer<void>? sendGate;

  /// So viele Übertragungen der Route liefen höchstens zugleich.
  int maxRouteSends = 0;
  int _routeSends = 0;

  @override
  Future<WatchSendResult> send(List<Map<String, Object>> messages) async {
    sent.add(messages);
    final route = messages.isNotEmpty && messages.first['t'] == 'r';
    if (route) {
      _routeSends++;
      if (_routeSends > maxRouteSends) maxRouteSends = _routeSends;
      try {
        await sendGate?.future;
      } finally {
        _routeSends--;
      }
    }
    final ch = channel;
    if (ch != null) return _through(ch, messages);
    if (autoStore && result.ok && messages.isNotEmpty && messages.first['t'] == 'r') {
      answer({'t': 'ok', 'id': messages.first['id']});
    }
    return result.ok ? WatchSendResult('SUCCESS', messages.length) : result;
  }

  /// Senden über den gemessenen Kanal: eine Nachricht nach der anderen,
  /// jede mit ihrer Laufzeit. Eine geschlossene App oder ein Verlust
  /// ändern am Ergebnis nichts — Garmin Connect weiß davon nichts.
  Future<WatchSendResult> _through(WatchChannel ch, List<Map<String, Object>> messages) async {
    final before = _line;
    final done = Completer<void>();
    _line = done.future;
    await before;
    try {
      final route = messages.isNotEmpty && messages.first['t'] == 'r';
      final failAfter = route ? ch.failRouteAfter : null;
      if (route) ch.failRouteAfter = null;
      var n = 0;
      for (final m in messages) {
        if (failAfter != null && n >= failAfter) return WatchSendResult('FAILURE_DURING_TRANSFER', n);
        await Future<void>.delayed(ch.delayOf(m));
        final k = _seq++;
        n++;
        if (!ch.appOpen || ch.lose.contains(k)) continue;
        delivered.add((at: (now ?? DateTime.now)(), msg: m));
        _arrive(m);
      }
      return WatchSendResult('SUCCESS', n);
    } finally {
      done.complete();
    }
  }

  /// Eine einfache Uhr-App am Kanal: Ist eine Route ganz angekommen,
  /// sagt sie „gespeichert“ ([autoStore]) — auf dem Rückweg so langsam wie
  /// hin.
  void _arrive(Map<String, Object> m) {
    if (!autoStore || m['t'] != 'r') return;
    final id = m['id'] as String, n = m['n'] as int;
    final got = _arrived.putIfAbsent(id, () => <int>{})..add(m['p'] as int);
    if (got.length == n) fromWatch({'t': 'ok', 'id': id});
  }

  /// Eine Nachricht der Uhr-App, die über den Kanal [after] (ab Werk die
  /// Laufzeit einer kleinen Nachricht) braucht; ohne Kanal sofort.
  void fromWatch(Map<String, Object> message, {Duration? after}) {
    final delay = after ?? channel?.small;
    if (delay == null) return answer(message);
    unawaited(Future<void>.delayed(delay, () => answer(message)));
  }

  /// Die Arten, die die Uhr-App erreichten, der Reihe nach.
  List<String> get deliveredTypes => [for (final d in delivered) d.msg['t'] as String];

  @override
  Future<WatchOpen> open() async {
    opens++;
    return openResult;
  }

  /// So oft wurde gelauscht ([GarminBridge.listen], #484).
  int listens = 0;

  @override
  Future<bool> listen() async {
    listens++;
    return status_.device != null;
  }

  /// Die Antworten auf Fahrten (`wk`) und „schick" (`wq`).
  List<Map<String, Object>> get rideAnswers =>
      [for (final batch in sent) ...batch.where((m) => m['t'] == 'wk' || m['t'] == 'wq')];

  void answer(Object? message) => _messages.add(message);

  /// Garmin Connect meldet die Uhr wieder verbunden.
  void reconnect() => _connected.add(null);

  /// Die Uhr-App startet und meldet sich mit der Route, die sie hat.
  void hello(String? id, {int? v = kWatchProtocol}) => answer({'t': 'hi', 'id': ?id, 'v': ?v});

  /// Die Positionen des Handys an die Uhr (`p`).
  List<Map<String, Object>> get positions => [for (final batch in sent) ...batch.where((m) => m['t'] == 'p')];

  /// Alle gesendeten Stücke der Route (ohne Bestwerte).
  List<Map<String, Object>> get routeParts =>
      [for (final batch in sent) ...batch.where((m) => m['t'] == 'r')];

  List<Map<String, Object>> get bests => [for (final batch in sent) ...batch.where((m) => m['t'] == 'b')];

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Stream<void> get connected => _connected.stream;

  /// Die Anfragen „welche Route hast du?" (`q`).
  int get queries => [for (final batch in sent) ...batch.where((m) => m['t'] == 'q')].length;
}
