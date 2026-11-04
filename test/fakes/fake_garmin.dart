import 'dart:async';

import 'package:trailbuddy/features/garmin/garmin_bridge.dart';

/// Die Garmin-Uhr im Test (Konzept-Garmin 3): ab Werk keine — wie ein
/// Telefon ohne Garmin Connect. Mit [status] eine verbundene Uhr; was
/// gesendet wird, liegt in [sent], [answer] spielt die Antwort der Uhr.
class FakeGarminBridge implements GarminBridge {
  FakeGarminBridge({this.status_ = WatchStatus.none, this.result = const WatchSendResult('SUCCESS', 0)});

  /// Eine verbundene fēnix 5 mit unserer App.
  FakeGarminBridge.connected({String device = 'fēnix 5', this.result = const WatchSendResult('SUCCESS', 0)})
      : status_ = WatchStatus(connect: true, device: device, app: WatchApp.installed);

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

  @override
  bool get supported => true;

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
    if (autoStore && result.ok && messages.isNotEmpty && messages.first['t'] == 'r') {
      answer({'t': 'ok', 'id': messages.first['id']});
    }
    return result.ok ? WatchSendResult('SUCCESS', messages.length) : result;
  }

  @override
  Future<WatchOpen> open() async {
    opens++;
    return openResult;
  }

  void answer(Object? message) => _messages.add(message);

  /// Garmin Connect meldet die Uhr wieder verbunden.
  void reconnect() => _connected.add(null);

  /// Die Uhr-App startet und meldet sich mit der Route, die sie hat.
  void hello(String? id) => answer({'t': 'hi', 'id': ?id, 'v': 1});

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
