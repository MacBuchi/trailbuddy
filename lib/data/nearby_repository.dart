// Buddy in der Nähe (#526, Patch 031) — was das Gerät dafür mit dem
// Server spricht.
//
// **Zwei Wege, beide schmal.** Die Schalter je Buddy liegen in
// `buddy_nearby_prefs` (eine Zeile nur bei Abweichung, RLS: nur der
// Besitzer). Die Zelle geht als Presence in den eigenen privaten
// Realtime-Kanal `nearby:<uid>`; die Buddys hören in ihren Kanälen zu.
// Wer welchen Kanal lesen darf, entscheiden die Policies auf
// `realtime.messages` (matcher_check.sql Block 34) — die App versucht
// einfach, und ein abgelehnter Beitritt heißt „nichts zu hören".
//
// **Gruppenfahrt** (#519, Patch 032): Wer in einer Fahrt „Live mit
// Buddys" anhat, setzt `l` an seiner Zelle und legt seine GENAUE Position
// in Paarkanäle `live:<a>:<b>` — aber nur mit den Buddys, die
// `livePairsFor` nennt (in der Nähe, Live auch an). Wer mich als Homie
// gewählt hat, sagt `nearby_homie_owners()`.
//
// **Kein Speicher, kein Korb** (A3, A8): Ohne Empfang wird nichts geteilt
// und nichts gemeldet. Ein altes „in der Nähe" gibt es nicht — Presence
// verschwindet mit der Verbindung.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/nearby/nearby_core.dart' show livePairTopic;

/// Die Schalter für EINEN Buddy. Vorgabe: er sieht mich, ich bekomme
/// seine Meldung, und er ist kein Homie.
class NearbyPref {
  const NearbyPref({
    required this.buddyId,
    this.hidden = false,
    this.muted = false,
    this.homie = false,
  });

  final String buddyId;

  /// „Sieht mich" aus — er kann meinen Kanal nicht lesen.
  final bool hidden;

  /// „Meldungen von ihm" aus — ich höre zu, melde ihn aber nicht.
  final bool muted;

  /// Homie (#519): Er sieht meine grobe Zelle auf der Karte, auch wenn er
  /// nicht in der Nähe ist.
  final bool homie;

  /// Alles auf der Vorgabe — dann gibt es keine Zeile.
  bool get isDefault => !hidden && !muted && !homie;

  NearbyPref copyWith({bool? hidden, bool? muted, bool? homie}) => NearbyPref(
    buddyId: buddyId,
    hidden: hidden ?? this.hidden,
    muted: muted ?? this.muted,
    homie: homie ?? this.homie,
  );

  factory NearbyPref.fromJson(Map<String, dynamic> j) => NearbyPref(
    buddyId: j['buddy_id'] as String,
    hidden: j['hidden'] as bool? ?? false,
    muted: j['muted'] as bool? ?? false,
    homie: j['homie'] as bool? ?? false,
  );
}

/// Ein Buddy hat seine Zelle gesetzt ([cell] `"zeile:spalte"`) oder ist
/// weg (null); [live]: er hat in dieser Fahrt „Live mit Buddys" an.
typedef NearbyCellEvent = ({String buddyId, String? cell, bool live});

/// Ein Buddy hat im Paarkanal seine genaue Position gesetzt ([lat]/[lon],
/// [at] seine Uhr) oder ist gegangen (alles null).
typedef LivePositionEvent = ({
  String buddyId,
  double? lat,
  double? lon,
  DateTime? at,
});

class NearbyRepository {
  NearbyRepository(this._client);

  final SupabaseClient _client;

  /// Exakt diese Spalten prüft `tool/schema_check.sh`.
  static const prefColumns = 'buddy_id, hidden, muted, homie';

  /// Wie lange ein Beitritt dauern darf, bevor er als gescheitert gilt.
  static const joinTimeout = Duration(seconds: 15);

  RealtimeChannel? _own;
  String? _ownUid;
  final _listening = <String, RealtimeChannel>{};
  final _cells = StreamController<NearbyCellEvent>.broadcast();
  final _pairs = <String, RealtimeChannel>{};
  final _joinedPairs = <String>{};
  Map<String, Object>? _livePayload;
  final _positions = StreamController<LivePositionEvent>.broadcast();

  /// Meine Schalter, je Buddy, für den ich etwas umgelegt habe.
  Future<List<NearbyPref>> fetchPrefs() async {
    final rows = await _client.from('buddy_nearby_prefs').select(prefColumns);
    return [for (final row in rows) NearbyPref.fromJson(row)];
  }

  /// Setzt beide Schalter für [buddyId]; zurück auf die Vorgabe löscht die
  /// Zeile.
  Future<void> setPref(NearbyPref pref) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    if (pref.isDefault) {
      await _client
          .from('buddy_nearby_prefs')
          .delete()
          .eq('user_id', uid)
          .eq('buddy_id', pref.buddyId);
      return;
    }
    await _client.from('buddy_nearby_prefs').upsert({
      'user_id': uid,
      'buddy_id': pref.buddyId,
      'hidden': pref.hidden,
      'muted': pref.muted,
      'homie': pref.homie,
    }, onConflict: 'user_id,buddy_id');
  }

  /// Wer hat MICH als Homie gewählt? (Patch 032)
  Future<Set<String>> fetchHomieOwners() async {
    final rows = await _client.rpc<List<dynamic>>('nearby_homie_owners');
    return {
      for (final r in rows)
        if (r is String) r,
    };
  }

  /// Die Zellen der Buddys, denen ich zuhöre.
  Stream<NearbyCellEvent> get cells => _cells.stream;

  /// Legt meine Zelle in meinen Kanal; null nimmt sie heraus und verlässt
  /// ihn. [live]: „Live mit Buddys" ist in dieser Fahrt an. Wirft, wenn der
  /// Beitritt scheitert (kein Empfang) — der Aufrufer versucht es beim
  /// nächsten Takt wieder.
  Future<void> share(String? cell, {bool live = false}) async {
    final uid = _client.auth.currentUser?.id;
    if (cell == null || uid == null || uid != _ownUid) {
      final own = _own;
      _own = null;
      _ownUid = null;
      if (own != null) {
        try {
          await own.untrack();
        } catch (_) {
          // Ohne Verbindung gibt es nichts herauszunehmen — Presence
          // verschwindet mit dem Kanal ohnehin.
        }
        await _client.removeChannel(own);
      }
      if (cell == null || uid == null) return;
    }
    var own = _own;
    if (own == null) {
      own = _client.channel(
        'nearby:$uid',
        opts: const RealtimeChannelConfig(private: true, enabled: true),
      );
      _own = own;
      _ownUid = uid;
      try {
        await _join(own);
      } catch (_) {
        _own = null;
        _ownUid = null;
        await _client.removeChannel(own);
        rethrow;
      }
    }
    await own.track({'c': cell, if (live) 'l': true});
  }

  /// Hört genau den Kanälen von [buddyIds] zu: neue dazu, alte weg.
  Future<void> listen(Set<String> buddyIds) async {
    for (final id in _listening.keys.toList()) {
      if (buddyIds.contains(id)) continue;
      final ch = _listening.remove(id)!;
      _cells.add((buddyId: id, cell: null, live: false));
      await _client.removeChannel(ch);
    }
    for (final id in buddyIds) {
      if (_listening.containsKey(id)) continue;
      final ch = _client.channel(
        'nearby:$id',
        opts: const RealtimeChannelConfig(private: true),
      );
      void emit() {
        String? cell;
        var live = false;
        for (final state in ch.presenceState()) {
          for (final p in state.presences) {
            final c = p.payload['c'];
            if (c is String) {
              cell = c;
              live = p.payload['l'] == true;
            }
          }
        }
        _cells.add((buddyId: id, cell: cell, live: live));
      }

      ch
          .onPresenceSync((_) => emit())
          .onPresenceJoin((_) => emit())
          .onPresenceLeave((_) => emit());
      _listening[id] = ch;
      ch.subscribe((status, _) {
        // Abgelehnt (nicht mehr Buddy, „sieht mich" aus) oder getrennt:
        // nichts zu hören. Der nächste Abgleich versucht es neu.
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (_listening[id] == ch) {
            _listening.remove(id);
            _cells.add((buddyId: id, cell: null, live: false));
            unawaited(_client.removeChannel(ch));
          }
        }
      });
    }
  }

  /// Die genauen Positionen aus den Paarkanälen.
  Stream<LivePositionEvent> get positions => _positions.stream;

  /// Hält genau mit [buddyIds] einen Paarkanal offen: neue dazu, alte weg.
  /// Wer drin ist, bekommt meine Position ([trackLive]).
  Future<void> livePairs(Set<String> buddyIds) async {
    final uid = _client.auth.currentUser?.id;
    for (final id in _pairs.keys.toList()) {
      if (uid != null && buddyIds.contains(id)) continue;
      final ch = _pairs.remove(id)!;
      _joinedPairs.remove(id);
      _positions.add((buddyId: id, lat: null, lon: null, at: null));
      try {
        await ch.untrack();
      } catch (_) {
        // Ohne Verbindung: Presence geht mit dem Kanal.
      }
      await _client.removeChannel(ch);
    }
    if (uid == null) return;
    for (final id in buddyIds) {
      if (_pairs.containsKey(id)) continue;
      final ch = _client.channel(
        livePairTopic(uid, id),
        opts: const RealtimeChannelConfig(private: true, enabled: true),
      );
      void emit() {
        LivePositionEvent e = (buddyId: id, lat: null, lon: null, at: null);
        for (final state in ch.presenceState()) {
          for (final p in state.presences) {
            if (p.payload['u'] != id) continue;
            final pos = p.payload['p'];
            final t = p.payload['t'];
            if (pos is List &&
                pos.length == 2 &&
                pos[0] is num &&
                pos[1] is num &&
                t is int) {
              e = (
                buddyId: id,
                lat: (pos[0] as num).toDouble(),
                lon: (pos[1] as num).toDouble(),
                at: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
              );
            }
          }
        }
        _positions.add(e);
      }

      ch
          .onPresenceSync((_) => emit())
          .onPresenceJoin((_) => emit())
          .onPresenceLeave((_) => emit());
      _pairs[id] = ch;
      ch.subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _joinedPairs.add(id);
          final payload = _livePayload;
          if (payload != null && _pairs[id] == ch) {
            unawaited(_trackIn(ch, payload));
          }
          return;
        }
        // Abgelehnt (ausgeschlossen, nicht mehr Buddy) oder getrennt: Der
        // nächste Abgleich versucht es neu; die letzte Position bleibt mit
        // ihrer Zeit stehen (die Karte sagt „zuletzt vor …").
        if (_pairs[id] == ch) {
          _pairs.remove(id);
          _joinedPairs.remove(id);
          unawaited(_client.removeChannel(ch));
        }
      });
    }
  }

  /// Legt meine genaue Position in jeden offenen Paarkanal. Fünf
  /// Nachkommastellen (~1 m) — mehr weiß das GPS nicht.
  Future<void> trackLive(double lat, double lon, DateTime at) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final payload = <String, Object>{
      'u': uid,
      'p': [
        double.parse(lat.toStringAsFixed(5)),
        double.parse(lon.toStringAsFixed(5)),
      ],
      't': at.toUtc().millisecondsSinceEpoch,
    };
    _livePayload = payload;
    for (final id in _joinedPairs.toList()) {
      final ch = _pairs[id];
      if (ch != null) await _trackIn(ch, payload);
    }
  }

  Future<void> _trackIn(RealtimeChannel ch, Map<String, Object> payload) async {
    try {
      await ch.track(payload);
    } catch (_) {
      // Kein Empfang: Der nächste Takt setzt sie wieder.
    }
  }

  /// Alles schließen (Abmelden, App weg).
  Future<void> close() async {
    _livePayload = null;
    await livePairs(const {});
    await share(null);
    await listen(const {});
  }

  Future<void> _join(RealtimeChannel ch) {
    final done = Completer<void>();
    ch.subscribe((status, error) {
      if (done.isCompleted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        done.complete();
      } else {
        done.completeError(error ?? StateError('nearby: $status'));
      }
    });
    return done.future.timeout(joinTimeout);
  }
}
