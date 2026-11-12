// Das Uhr-Protokoll (#510, Prüfleiter T4 in docs/konzept-garmin.md 12):
// Die Uhr-App hält die letzten 120 Ereignisse ihres Ablaufkerns
// (`garmin/source/EventLog.mc`) und gibt sie mit jeder Fahrt (`w`, Schlüssel
// `ev` in der ersten Nachricht) und nach einem Absturz mit dem nächsten
// „hallo" (`hi`, `ev`). Pur — kein Kanal, keine Datei; die Ablage ist
// `watch_event_store.dart`, das Anhängen der Feedback-Dialog.
//
// Je Ereignis eine Zahl: `(Art << 27) | (Detail << 24) | Sekunden seit dem
// Start der Uhr-App`. Keine Koordinaten, keine Kennungen, keine Namen
// (A7). Die Tabelle steht dreimal und muss gleich bleiben: EventLog.mc,
// `tool/garmin_events.py` und hier — `test/garmin/watch_events_test.dart`
// liest die Arten der Nachrichten aus EventLog.mc.
import 'dart:convert';
import 'dart:typed_data';

/// So viele Ereignisse hält die Uhr (`EventLog.SIZE`); mehr nimmt das
/// Handy nicht an.
const kWatchEventsMax = 120;

/// So lange bietet der Feedback-Dialog ein Protokoll zum Anhängen an.
const kWatchEventsOffer = Duration(days: 1);

/// Die Arten der Nachrichten, wie die Uhr sie zählt (`EventLog.IN_T`,
/// `OUT_T`: je drei Zeichen ab Stelle 0).
const kWatchEventsIn = ' q  wq wk p  n  k  e  r  b  ';
const kWatchEventsOut = ' hi x  ok g  d  e  rs re rp rr rt w  ';

/// Die Kennung der Zeile im Feedback-Text, die `tool/garmin_events.py`
/// sucht.
const kWatchEventsTag = 'ev1:';

List<String> _types(String s) => [for (var i = 0; i + 1 < s.length; i += 3) s.substring(i, i + 3).trim()];

/// Ein Ereignis, entpackt.
typedef WatchEvent = ({int kind, int detail, int sec});

WatchEvent unpackWatchEvent(int v) {
  final u = v & 0xFFFFFFFF;
  return (kind: (u >> 27) & 0x1F, detail: (u >> 24) & 7, sec: u & 0xFFFFFF);
}

int packWatchEvent(int kind, int detail, int sec) {
  final v = (kind << 27) | ((detail & 7) << 24) | (sec & 0xFFFFFF);
  return v >= 1 << 31 ? v - (1 << 32) : v;
}

/// Der Ring aus einer Nachricht (`ev`), oder null, wenn er fehlt oder
/// nicht passt (keine Liste, keine Zahl, zu lang).
List<int>? watchEventsOf(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > kWatchEventsMax) return null;
  final out = <int>[];
  for (final v in raw) {
    if (v is! int) return null;
    out.add(v);
  }
  return out;
}

/// Ein Ereignis als Teile der Zeile für die Liste im Dialog: `[Art,
/// Detail]` — Art und Detail sind Schlüssel für die Übersetzung
/// (`WatchEventLabels`), Nachrichten ihre Kurzform (`hi`, `wq`).
({String kind, String detail}) watchEventParts(int v) {
  final e = unpackWatchEvent(v);
  switch (e.kind) {
    case 3:
    case 4:
    case 5:
    case 6:
      final table = _types(e.kind <= 4 ? kWatchEventsIn : kWatchEventsOut);
      final i = e.detail + (e.kind == 4 || e.kind == 6 ? 8 : 0);
      final unknown = (e.kind == 4 || e.kind == 6) && e.detail == 7;
      return (kind: e.kind <= 4 ? 'in' : 'out', detail: unknown || i >= table.length ? '?' : table[i]);
  }
  const kinds = {0: 'start', 1: 'key', 2: 'menu', 7: 'sent', 8: 'state', 9: 'fix', 10: 'due'};
  return (kind: kinds[e.kind] ?? 'other', detail: '${e.detail}');
}

/// Kompakt für den Feedback-Text (die Zeile darf nicht viel kosten:
/// `feedback.message` hat höchstens 2000 Zeichen): je Ereignis ein Byte
/// Code und die Sekunden seit dem vorigen als Varint, base64url ohne `=`,
/// mit [kWatchEventsTag] davor. 120 Ereignisse sind meist unter 400
/// Zeichen, höchstens 645.
String encodeWatchEvents(List<int> events) {
  final bytes = BytesBuilder();
  var last = 0;
  for (final v in events) {
    final e = unpackWatchEvent(v);
    bytes.addByte((e.kind << 3) | e.detail);
    var d = e.sec - last;
    if (d < 0) d = 0;
    last = e.sec;
    while (d >= 0x80) {
      bytes.addByte((d & 0x7F) | 0x80);
      d >>= 7;
    }
    bytes.addByte(d);
  }
  return '$kWatchEventsTag${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';
}

/// Das Gegenstück zu [encodeWatchEvents] (Tests; `tool/garmin_events.py`
/// liest dieselbe Form), null bei kaputter Eingabe.
List<int>? decodeWatchEvents(String text) {
  final i = text.indexOf(kWatchEventsTag);
  if (i < 0) return null;
  var s = text.substring(i + kWatchEventsTag.length).split(RegExp(r'\s')).first;
  while (s.length % 4 != 0) {
    s += '=';
  }
  final Uint8List bytes;
  try {
    bytes = base64Url.decode(s);
  } on FormatException {
    return null;
  }
  final out = <int>[];
  var sec = 0;
  var p = 0;
  while (p < bytes.length) {
    final code = bytes[p++];
    var d = 0, shift = 0;
    while (true) {
      if (p >= bytes.length) return null;
      final b = bytes[p++];
      d |= (b & 0x7F) << shift;
      shift += 7;
      if (b < 0x80) break;
    }
    sec += d;
    out.add(packWatchEvent(code >> 3, code & 7, sec));
  }
  return out;
}

/// Ein abgelegtes Protokoll: wann es ankam, woher ([fromCrash]: mit dem
/// „hallo" nach einem Absturz, sonst mit einer Fahrt) und die Ereignisse.
class WatchEventLog {
  const WatchEventLog({required this.at, required this.fromCrash, required this.events});

  final DateTime at;
  final bool fromCrash;
  final List<int> events;

  Map<String, Object?> toJson() =>
      {'at': at.toUtc().toIso8601String(), 'crash': fromCrash, 'ev': events};

  static WatchEventLog? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final ev = watchEventsOf(j['ev']);
    if (at == null || ev == null) return null;
    return WatchEventLog(at: at, fromCrash: j['crash'] == true, events: ev);
  }
}
