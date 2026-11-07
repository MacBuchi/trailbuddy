// Airtime unter Buddys (#36 Schritt 6, Patch 029; docs/konzept-airtime.md
// Abschnitt 4 und 5).
//
// **Zwei Dinge verlassen das Gerät**: der eigene Bestwert je Trail
// (`trail_airtime`, nur über `set_trail_airtime` — der Server behält das
// Bessere und prüft, dass ich den Trail sehe) und EINE Zeile je Nutzer mit
// dem Zähler der letzten 30 Tage (`airtime_counters`). Wer was sieht,
// entscheidet die RLS; hier steht nur, was die App liest und schickt.
//
// **Kein Ausgangskorb**: Die eigenen Fahrten SIND der Korb. Der Abgleich
// (`airtime_sync.dart`) rechnet bei jedem Lauf alles neu und schickt es
// ganz; was ohne Netz liegen bleibt, geht beim nächsten Lauf mit.
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

/// Die Titel, die das GERÄT vergibt (Konzept 5) — die Schlüssel stehen so
/// im Check von `airtime_counters.titles`. Vielflieger und Trailkönig
/// rechnet die App des Betrachters (`airtime_share.dart`).
enum AirtimeTitle {
  /// Ein einzelner Sprung ≥ 1,0 s in den letzten 30 Tagen.
  glider('glider'),

  /// Im Fenster gemessen gefahren, aber kein Sprung.
  groundCrew('ground_crew');

  const AirtimeTitle(this.key);

  final String key;

  static AirtimeTitle? fromKey(String key) =>
      values.where((t) => t.key == key).firstOrNull;
}

/// Ein Bestwert je Trail und Nutzer, so wie er auf dem Server steht.
class TrailAirtime {
  const TrailAirtime({
    required this.userId,
    required this.trailId,
    required this.airDs,
    required this.longestDs,
    required this.month,
  });

  final String userId;
  final String trailId;

  /// Die beste Airtime EINER Durchfahrt, Summe der Sprünge, in Zehntelsekunden.
  final int airDs;

  /// Der längste einzelne Sprung, in Zehntelsekunden.
  final int longestDs;

  /// Der Monat des Bestwerts (der Erste des Monats) — nie der Tag.
  final DateTime month;

  factory TrailAirtime.fromJson(Map<String, dynamic> j) => TrailAirtime(
        userId: j['user_id'] as String,
        trailId: j['trail_id'] as String,
        airDs: (j['air_ds'] as num).toInt(),
        longestDs: (j['longest_ds'] as num).toInt(),
        month: DateTime.parse(j['month'] as String),
      );
}

/// Was das Gerät für einen Trail hochlädt.
class TrailAirtimeUpload {
  const TrailAirtimeUpload({
    required this.trailId,
    required this.airDs,
    required this.longestDs,
    required this.month,
  });

  final String trailId;
  final int airDs;
  final int longestDs;
  final DateTime month;

  Map<String, dynamic> toJson() => {
        'trail_id': trailId,
        'air_ds': airDs,
        'longest_ds': longestDs,
        'month': _day(DateTime(month.year, month.month)),
      };
}

/// Der Zähler eines Nutzers: Airtime und Sprünge der letzten 30 Tage,
/// gerechnet am Tag [asOf] auf seinem Gerät.
class AirtimeCounter {
  const AirtimeCounter({
    required this.userId,
    required this.airDs,
    required this.jumps,
    required this.asOf,
    this.titles = const {},
  });

  final String userId;
  final int airDs;
  final int jumps;
  final DateTime asOf;
  final Set<AirtimeTitle> titles;

  factory AirtimeCounter.fromJson(Map<String, dynamic> j) => AirtimeCounter(
        userId: j['user_id'] as String,
        airDs: (j['air_ds'] as num).toInt(),
        jumps: (j['jumps'] as num).toInt(),
        asOf: DateTime.parse(j['as_of'] as String),
        titles: {
          for (final k in (j['titles'] as List? ?? const [])) ?AirtimeTitle.fromKey(k as String),
        },
      );
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class AirtimeRepository {
  AirtimeRepository(this._client);

  final SupabaseClient _client;

  /// Exakt diese Spalten prüft `tool/schema_check.sh`.
  static const bestColumns = 'user_id, trail_id, air_ds, longest_ds, month';
  static const counterColumns = 'user_id, air_ds, jumps, as_of, titles';

  /// Alle Bestwerte, die ich sehen darf — eigene und die der Buddys auf
  /// Trails, die ich sehe. Wenige Zeilen: Buddys mal ihre Trails.
  Future<List<TrailAirtime>> fetchBests() async {
    final rows = await _client.from('trail_airtime').select(bestColumns);
    return [for (final row in rows) TrailAirtime.fromJson(row)];
  }

  /// Mein Zähler und die meiner Buddys.
  Future<List<AirtimeCounter>> fetchCounters() async {
    final rows = await _client.from('airtime_counters').select(counterColumns);
    return [for (final row in rows) AirtimeCounter.fromJson(row)];
  }

  /// Schickt alle Bestwerte des Geräts; der Server behält das Bessere.
  /// Gibt zurück, wie viele neu oder besser wurden.
  Future<int> uploadBests(List<TrailAirtimeUpload> bests) async {
    if (bests.isEmpty) return 0;
    final n = await _client.rpc('set_trail_airtime',
        params: {'items': [for (final b in bests) b.toJson()]});
    return (n as num?)?.toInt() ?? 0;
  }

  /// Überschreibt meinen Zähler.
  Future<void> setCounter({
    required int airDs,
    required int jumps,
    required DateTime asOf,
    required Set<AirtimeTitle> titles,
  }) async {
    await _client.from('airtime_counters').upsert({
        'user_id': _client.requireUid,
        'air_ds': airDs,
        'jumps': jumps,
        'as_of': _day(asOf),
        'titles': [for (final t in titles) t.key],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
  }

  /// Schalter aus: alles Geteilte weg, in einer Transaktion.
  Future<void> deleteMine() async {
    await _client.rpc('delete_my_airtime');
  }
}
