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
// **Kein Speicher, kein Korb** (A3, A8): Ohne Empfang wird nichts geteilt
// und nichts gemeldet. Ein altes „in der Nähe" gibt es nicht — Presence
// verschwindet mit der Verbindung.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Die beiden Schalter für EINEN Buddy. Vorgabe: er sieht mich, und ich
/// bekomme seine Meldung.
class NearbyPref {
  const NearbyPref({required this.buddyId, this.hidden = false, this.muted = false});

  final String buddyId;

  /// „Sieht mich" aus — er kann meinen Kanal nicht lesen.
  final bool hidden;

  /// „Meldungen von ihm" aus — ich höre zu, melde ihn aber nicht.
  final bool muted;

  factory NearbyPref.fromJson(Map<String, dynamic> j) => NearbyPref(
        buddyId: j['buddy_id'] as String,
        hidden: j['hidden'] as bool? ?? false,
        muted: j['muted'] as bool? ?? false,
      );
}

/// Ein Buddy hat seine Zelle gesetzt ([cell] `"zeile:spalte"`) oder ist
/// weg (null).
typedef NearbyCellEvent = ({String buddyId, String? cell});

class NearbyRepository {
  NearbyRepository(this._client);

  final SupabaseClient _client;

  /// Exakt diese Spalten prüft `tool/schema_check.sh`.
  static const prefColumns = 'buddy_id, hidden, muted';

  /// Wie lange ein Beitritt dauern darf, bevor er als gescheitert gilt.
  static const joinTimeout = Duration(seconds: 15);

  RealtimeChannel? _own;
  String? _ownUid;
  final _listening = <String, RealtimeChannel>{};
  final _cells = StreamController<NearbyCellEvent>.broadcast();

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
    if (!pref.hidden && !pref.muted) {
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
    }, onConflict: 'user_id,buddy_id');
  }

  /// Die Zellen der Buddys, denen ich zuhöre.
  Stream<NearbyCellEvent> get cells => _cells.stream;

  /// Legt meine Zelle in meinen Kanal; null nimmt sie heraus und verlässt
  /// ihn. Wirft, wenn der Beitritt scheitert (kein Empfang) — der Aufrufer
  /// versucht es beim nächsten Takt wieder.
  Future<void> share(String? cell) async {
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
      own = _client.channel('nearby:$uid',
          opts: const RealtimeChannelConfig(private: true, enabled: true));
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
    await own.track({'c': cell});
  }

  /// Hört genau den Kanälen von [buddyIds] zu: neue dazu, alte weg.
  Future<void> listen(Set<String> buddyIds) async {
    for (final id in _listening.keys.toList()) {
      if (buddyIds.contains(id)) continue;
      final ch = _listening.remove(id)!;
      _cells.add((buddyId: id, cell: null));
      await _client.removeChannel(ch);
    }
    for (final id in buddyIds) {
      if (_listening.containsKey(id)) continue;
      final ch = _client.channel('nearby:$id', opts: const RealtimeChannelConfig(private: true));
      void emit() {
        String? cell;
        for (final state in ch.presenceState()) {
          for (final p in state.presences) {
            final c = p.payload['c'];
            if (c is String) cell = c;
          }
        }
        _cells.add((buddyId: id, cell: cell));
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
            _cells.add((buddyId: id, cell: null));
            unawaited(_client.removeChannel(ch));
          }
        }
      });
    }
  }

  /// Alles schließen (Abmelden, App weg).
  Future<void> close() async {
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
