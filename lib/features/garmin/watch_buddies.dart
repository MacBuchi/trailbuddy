// Was die Uhr von Ansagen und Buddys erfährt (#525, #526, #519;
// `docs/konzept-garmin.md` 1 und 4, `docs/konzept-geraete.md` 6.2/6.3) —
// rein, Nachrichten im Format der Uhr (`garmin/source/WatchCore.mc`,
// `cue` und `showBuddies`).
//
// - **Ein Moment der Ansagen** (Trail voraus, beginnt, geschafft) ist an
//   der Uhr eine kurze Vibration mit Schild und Name: `{t: "c", k: "tr",
//   n, g}`. Abkommen und Ankunft erkennt die Uhr selbst — das Handy
//   schickt sie nicht noch einmal (sonst vibrierte sie doppelt).
// - **Ein Buddy unterwegs**: `{t: "c", k: "bn", n}`, Scheibe mit Buchstabe.
// - **Gruppenfahrt**: `{t: "u", l: [[la, lo, Buchstabe, Alter s], …]}` —
//   nur genaue Positionen aus dem Paarkanal, nie die Zelle eines Homies
//   (5 km passen nicht auf eine Karte von 300 m). Höchstens
//   [kWatchBuddiesMax], die frischesten zuerst.
import 'dart:convert';

import '../nearby/buddy_map_layer.dart' show buddyInitial;
import '../nearby/nearby_core.dart' show BuddyMapEntry, BuddyMapKind;
import '../routing/voice_cues.dart' show VoiceCue, VoiceCueKind;
import 'watch_route.dart' show kWatchBuddies, kWatchCue;

/// So viele Buddys zeichnet die Uhr höchstens.
const kWatchBuddiesMax = 5;

/// Höchstens so oft geht die Liste an die Uhr — so oft kommt eine neue
/// Position aus dem Paarkanal ohnehin (`liveEvery`), und eine Nachricht
/// braucht ~3,5 s.
const kWatchBuddiesEvery = Duration(seconds: 15);

/// Der Hinweis zu einer Ansage, oder null für die, die die Uhr selbst
/// kennt (abseits, zurück, angekommen) und für einen Trail ohne Namen.
Map<String, Object>? watchVoiceCueOf(VoiceCue cue) {
  switch (cue.kind) {
    case VoiceCueKind.trailAhead || VoiceCueKind.trailStart || VoiceCueKind.trailDone:
      final name = cue.name?.trim() ?? '';
      if (name.isEmpty) return null;
      return {'t': kWatchCue, 'k': 'tr', 'n': name, if (cue.grade != null) 'g': cue.grade!};
    case VoiceCueKind.offRoute || VoiceCueKind.backOnRoute || VoiceCueKind.arrived:
      return null;
  }
}

/// Die Hinweise zu [cues] als Nachricht des Dienstes an die App
/// (`sendDataToMain` trägt nur einfache Werte, deshalb Text) — die Brücke
/// zur Uhr lebt in der App, nicht im Dienst. Null, wenn keiner an die Uhr
/// geht.
const kVoiceWatchMessagePrefix = 'voice:watch:';

String? encodeVoiceWatch(Iterable<VoiceCue> cues) {
  final out = [for (final c in cues) ?watchVoiceCueOf(c)];
  return out.isEmpty ? null : kVoiceWatchMessagePrefix + jsonEncode(out);
}

/// Die Hinweise aus [data], leer bei allem anderen. Wirft nie.
List<Map<String, Object>> decodeVoiceWatch(Object? data) {
  if (data is! String || !data.startsWith(kVoiceWatchMessagePrefix)) return const [];
  try {
    final raw = jsonDecode(data.substring(kVoiceWatchMessagePrefix.length));
    if (raw is! List) return const [];
    return [
      for (final m in raw)
        if (m is Map && m['t'] == kWatchCue && m['k'] == 'tr' && m['n'] is String)
          {'t': kWatchCue, 'k': 'tr', 'n': m['n'] as String, if (m['g'] is int) 'g': m['g'] as int},
    ];
  } catch (_) {
    return const [];
  }
}

/// „[name] ist auch unterwegs" an der Uhr.
Map<String, Object>? watchBuddyNearOf(String name) {
  final n = name.trim();
  return n.isEmpty ? null : {'t': kWatchCue, 'k': 'bn', 'n': n};
}

/// Die Buddys mit genauer Position für die Uhr — die Zelle eines Homies
/// bleibt am Handy. [nameOf] liefert den angezeigten Namen.
Map<String, Object> watchBuddiesOf(List<BuddyMapEntry> entries, String Function(String buddyId) nameOf) {
  final live = [
    for (final e in entries)
      if (e.kind == BuddyMapKind.live) e,
  ]..sort((a, b) => (a.seenAgo ?? Duration.zero).compareTo(b.seenAgo ?? Duration.zero));
  return {
    't': kWatchBuddies,
    'l': [
      for (final e in live.take(kWatchBuddiesMax))
        [
          (e.point.lat * 1e5).round(),
          (e.point.lon * 1e5).round(),
          buddyInitial(nameOf(e.buddyId)),
          (e.seenAgo ?? Duration.zero).inSeconds,
        ],
    ],
  };
}
