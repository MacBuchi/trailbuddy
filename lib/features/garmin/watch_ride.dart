// Die Fahrt von der Uhr (#484, docs/konzept-garmin.md 2a): Die Uhr-App
// zeichnet jede Fahrt selbst auf (`garmin/source/RideLog.mc`) und hält sie,
// bis das Handy sie mit `wk` quittiert. Pur — kein Kanal, kein Riverpod;
// `watch_ride_inbox.dart` empfängt und legt ab.
//
// Der Weg:
//   Uhr  → `{t: "hi", …, rq: [id, …]}`   wartende Fahrten im „hallo"
//   Handy → `{t: "wq"}`                   „schick"
//   Uhr  → `{t: "w", id, p, n, c}`       Nachricht p von n, `c` = Stücke
//   Handy → `{t: "wk", id}`              abgelegt (oder lag schon da)
//
// Ein Stück ist `[lat, lon, t, e, acc, p1, q1, p2, q2, …]`: der erste
// Punkt in 1e-5°, Sekunden seit 1970 (UTC), Höhe in Dezimetern, Klasse der
// Genauigkeit 0–3; danach je Punkt `p = (dLat << 16) | dLon` und
// `q = (dt << 16) | (dE << 2) | acc` gegen den Vorgänger, dE in dm mit 14
// Bit Vorzeichen.
import '../rides/ride_track.dart' show RidePoint;
import 'watch_route.dart' show watchPack, watchUnpack;

/// Eine Nachricht der Fahrt, „schick" und „abgelegt".
const kWatchRide = 'w';
const kWatchRidePull = 'wq';
const kWatchRideAck = 'wk';

/// Die Klassen der Genauigkeit der Uhr als Streuradius in Metern
/// (`Position.QUALITY_GOOD` → 0 … `NOT_AVAILABLE` → 3). Die Uhr nimmt nur
/// GOOD und USABLE; das Zerlege-Blatt verwirft über 30 m.
const kWatchAccuracyM = [5.0, 15.0, 40.0, 100.0];

/// „Schick die wartenden Fahrten" — die Antwort auf ein „hallo" mit `rq`.
const Map<String, Object> watchRidePull = {'t': kWatchRidePull};

/// „Die Fahrt [id] liegt auf dem Handy" — erst dann löscht die Uhr sie.
Map<String, Object> watchRideAckOf(String id) => {'t': kWatchRideAck, 'id': id};

/// Eine Nachricht der Fahrt: `(id, p, n, chunks)`, oder null bei falscher
/// Form.
({String id, int p, int n, List<List<int>> chunks})? watchRidePartOf(Object? message) {
  if (message is! Map || message['t'] != kWatchRide) return null;
  final id = message['id'], p = message['p'], n = message['n'], c = message['c'];
  if (id is! String || p is! int || n is! int || c is! List || n < 1 || p < 0 || p >= n) return null;
  final chunks = <List<int>>[];
  for (final chunk in c) {
    if (chunk is! List || chunk.length < 5 || chunk.length.isEven) return null;
    final ints = <int>[];
    for (final v in chunk) {
      if (v is! int) return null;
      ints.add(v);
    }
    chunks.add(ints);
  }
  return (id: id, p: p, n: n, chunks: chunks);
}

/// Die Stücke einer Fahrt als Punkte, in ihrer Reihenfolge — oder null,
/// wenn eins nicht passt (Zeit rückwärts, Lage außerhalb der Erde).
List<RidePoint>? decodeWatchRide(List<List<int>> chunks) {
  final out = <RidePoint>[];
  for (final c in chunks) {
    if (c.length < 5 || c.length.isEven) return null;
    var la = c[0], lo = c[1], t = c[2], e = c[3];
    var acc = c[4];
    for (var i = 4;; i += 2) {
      if (la < -9000000 || la > 9000000 || lo < -18000000 || lo > 18000000 || acc < 0 || acc > 3) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true);
      if (out.isNotEmpty && at.isBefore(out.last.at)) return null;
      out.add(RidePoint(lat: la / 1e5, lng: lo / 1e5, at: at, accuracyM: kWatchAccuracyM[acc], altM: e / 10));
      if (i + 2 >= c.length) break;
      final (dLat, dLon) = watchUnpack(c[i + 1]);
      final l = c[i + 2] & 0xffff;
      la += dLat;
      lo += dLon;
      t += (c[i + 2] >> 16 & 0xffff).toSigned(16);
      e += (l >> 2).toSigned(14);
      acc = l & 3;
    }
  }
  return out;
}

/// Gegenstück zu [decodeWatchRide] für die Tests: Punkte als `(lat, lon,
/// t, e, acc)` in den Einheiten der Uhr, je [perChunk] ein Stück, wie
/// `RideLog.add` packt.
List<List<int>> encodeWatchRide(List<(int, int, int, int, int)> points, {int perChunk = 60}) {
  final out = <List<int>>[];
  List<int>? c;
  var n = 0;
  late (int, int, int, int, int) last;
  for (final p in points) {
    if (c == null || n >= perChunk) {
      c = [p.$1, p.$2, p.$3, p.$4, p.$5];
      out.add(c);
      n = 1;
    } else {
      c.add(watchPack(p.$1 - last.$1, p.$2 - last.$2));
      c.add(watchPack(p.$3 - last.$3, ((p.$4 - last.$4) & 0x3fff) << 2 | p.$5));
      n++;
    }
    last = p;
  }
  return out;
}
