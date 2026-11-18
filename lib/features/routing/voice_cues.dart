// Ansagen übers Ohr (#525, Entscheidung E7 in `konzept-geraete.md`,
// A12 in `anforderungen.md`): Handy in der Tasche, Ohrhörer drin — die
// Momente, die man sonst nur auf dem Bildschirm sähe, kommen als kurzer
// Satz. **Keine Abbiegeansagen**: Der Graph kennt Kreuzungen nicht
// verlässlich, auf einem Trail löste jede Kehre eine aus
// (`konzept-routing.md` 9.6).
//
// Alles hier ist rein: Stand der Navigation rein, Ansagen raus; Punkt und
// Trails rein, Ansage raus. Gesprochen wird im Dienst
// (`voice_service.dart`); so ist jede Regel ohne Gerät geprüft
// (`test/routing/voice_cues_test.dart`).
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart' show Trail, gradeLabel;
import '../rides/ride_confirm.dart'
    show kConfirmMaxAccuracyM, kConfirmMinTravelM, kConfirmNearM;
import '../rides/ride_track.dart' show RidePoint;
import '../rides/trail_values.dart' show TrailValues;
import 'route_progress.dart';

/// So weit vor dem Trailkopf kommt „Trail …, in 200 Metern".
const kVoiceAheadM = 200.0;

/// Näher als das ist man schon am Kopf: Statt „in 20 Metern" kommt gleich
/// die Ansage beim Einfahren.
const kVoiceAtHeadM = 40.0;

/// So alt darf die Meldung eines Buddys sein, damit sie mit angesagt
/// wird — „frisch" (Betreiber 2026-11-17: „Baum quer, vor drei Tagen").
/// Text und Foto leben 90 Tage (#433); was älter als zwei Wochen ist,
/// steht am Trail, aber nicht im Ohr.
const kVoiceNoteFreshDays = 14;

enum VoiceCueKind {
  offRoute,
  backOnRoute,
  trailAhead,
  trailStart,
  trailDone,
  arrived,
}

/// Eine Ansage — was gesagt wird, steht erst in [voiceCueText].
class VoiceCue {
  const VoiceCue(
    this.kind, {
    this.name,
    this.grade,
    this.inM,
    this.duration,
    this.values,
    this.note,
  });

  final VoiceCueKind kind;
  final String? name;
  final int? grade;

  /// Ahead: Meter bis zum Kopf.
  final double? inM;

  /// Done: wie lange man auf dem Trail war.
  final Duration? duration;

  /// Done: Airtime und Co., wenn die Erkennung läuft.
  final TrailValues? values;

  /// Die frische Meldung eines Buddys zum Trail.
  final NavNote? note;
}

/// Ist [note] frisch genug für die Ansage — und nicht die eigene?
bool voiceNoteFresh(NavNote? note, {required DateTime now, String? selfId}) {
  if (note == null || note.body.trim().isEmpty) return false;
  if (selfId != null && note.authorId == selfId) return false;
  return now.difference(note.createdAt) <=
      const Duration(days: kVoiceNoteFreshDays);
}

/// Die Ansagen der Navigation: je Moment höchstens einmal, je Trail
/// „voraus", „beginnt" und „geschafft" je einmal — auch wenn die Route
/// unterwegs neu geplant wird und die Trails auf der Linie wandern.
class NavVoiceWatcher {
  NavVoiceWatcher({this.selfId});

  /// Das eigene Konto: Die eigene Meldung sagt niemand einem selbst an.
  final String? selfId;

  final _ahead = <String>{};
  final _started = <String>{};
  bool _reached = false;
  bool _saidOff = false;
  bool _arrived = false;
  NavTrailSection? _on;
  DateTime? _onSince;

  /// Ein Stand. [values] liefert die Trail-Werte seit einem Zeitpunkt
  /// (null ohne Erkennung).
  List<VoiceCue> update(
    NavState state,
    NavSections sections, {
    required DateTime now,
    TrailValues? Function(DateTime since)? values,
  }) {
    final out = <VoiceCue>[];
    if (state.offM <= kNavOffRouteM) _reached = true;
    // Abseits: einmal beim Verlassen, einmal beim Zurückkommen — aber erst,
    // nachdem man einmal auf der Route war (eine Fahrt aus „Meine Fahrten"
    // beginnt oft 600 m vor der Haustür).
    if (state.offRoute) {
      if (!_saidOff && _reached && !state.arrived) {
        _saidOff = true;
        out.add(const VoiceCue(VoiceCueKind.offRoute));
      }
      // Abseits ist der Stand auf der Linie geraten — kein Trail-Moment.
      return out;
    }
    if (_saidOff) {
      _saidOff = false;
      out.add(const VoiceCue(VoiceCueKind.backOnRoute));
    }
    final along = state.alongM;
    final current = sections.at(along);
    final on = _on;
    // Ankommen schließt den Trail, auf dem die Route endet — sonst käme
    // „geschafft" nie (im Test gefunden).
    if (on != null &&
        (current?.trailId != on.trailId || along > on.endM || state.arrived)) {
      final since = _onSince!;
      out.add(
        VoiceCue(
          VoiceCueKind.trailDone,
          name: on.name,
          duration: now.difference(since),
          values: values?.call(since),
        ),
      );
      _on = null;
      _onSince = null;
    }
    if (current != null && _on == null && !_started.contains(current.trailId)) {
      _started.add(current.trailId);
      final saidAhead = !_ahead.add(current.trailId);
      _on = current;
      _onSince = now;
      out.add(
        VoiceCue(
          VoiceCueKind.trailStart,
          name: current.name,
          grade: current.grade,
          // Wer die Ansage voraus gehört hat, kennt die Meldung schon.
          note:
              !saidAhead &&
                  voiceNoteFresh(current.note, now: now, selfId: selfId)
              ? current.note
              : null,
        ),
      );
    }
    if (_on == null) {
      final next = sections.nextFrom(along);
      if (next != null &&
          !_ahead.contains(next.trailId) &&
          !_started.contains(next.trailId)) {
        final inM = next.startM - along;
        if (inM <= kVoiceAheadM && inM > kVoiceAtHeadM) {
          _ahead.add(next.trailId);
          out.add(
            VoiceCue(
              VoiceCueKind.trailAhead,
              name: next.name,
              grade: next.grade,
              inM: inM,
              note: voiceNoteFresh(next.note, now: now, selfId: selfId)
                  ? next.note
                  : null,
            ),
          );
        }
      }
    }
    if (state.arrived && !_arrived) {
      _arrived = true;
      out.add(const VoiceCue(VoiceCueKind.arrived));
    }
    return out;
  }
}

/// Ein Trail für die freie Fahrt (F7): wer ohne Navigation in einen
/// bekannten Trail einfährt, hört Name und Grad. Die App legt die Trails
/// beim Start der Fahrt ab (`rides/voice_trails.json`), der Dienst liest
/// sie nur neu, wenn die Datei sich ändert — wie die Fragen aus #116.
class VoiceTrail {
  VoiceTrail({
    required this.trailId,
    required this.name,
    required this.line,
    this.grade,
    this.note,
  }) : box = LatBox.of(line);

  final String trailId;
  final String name;
  final int? grade;
  final List<LatLng> line;
  final LatBox box;
  final NavNote? note;

  Map<String, dynamic> toJson() => {
    'trail': trailId,
    'name': name,
    if (grade != null) 'grade': grade,
    if (note != null) 'note': note!.encode(),
    'line': [
      for (final p in line) [p.latitude, p.longitude],
    ],
  };

  static VoiceTrail? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['trail'];
    final raw = json['line'];
    if (id is! String || raw is! List) return null;
    final line = <LatLng>[
      for (final p in raw)
        if (p is List && p.length == 2 && p[0] is num && p[1] is num)
          LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    if (line.length < 2) return null;
    return VoiceTrail(
      trailId: id,
      name: json['name'] as String? ?? '',
      grade: (json['grade'] as num?)?.toInt(),
      note: NavNote.decode(json['note']),
      line: line,
    );
  }
}

/// Die Trails der freien Fahrt aus dem Netz: alle mit Linie, die beim
/// Server liegen, mit der jüngsten Meldung eines Buddys.
List<VoiceTrail> voiceTrailsOf(
  AppLocalizations l,
  Iterable<Trail> trails, {
  String? selfId,
}) => [
  for (final t in trails)
    if (!t.pending && t.points.length >= 2)
      VoiceTrail(
        trailId: t.id,
        name: t.displayName(l),
        grade: t.grade,
        line: t.points,
        note: latestBuddyNote(t, selfId: selfId),
      ),
];

String encodeVoiceTrails({
  required String uid,
  required List<VoiceTrail> trails,
}) => jsonEncode({
  'uid': uid,
  'trails': [for (final t in trails) t.toJson()],
});

List<VoiceTrail> decodeVoiceTrails(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['uid'] != uid) return const [];
    final raw = json['trails'];
    if (raw is! List) return const [];
    return [for (final t in raw) ?VoiceTrail.fromJson(t)];
  } catch (_) {
    return const [];
  }
}

/// Die freie Fahrt: Einfahren heißt dieselbe Regel wie die Frage aus #116
/// (`confirmPromptFor`) — zwei scharfe Fixe im Korridor derselben Linie,
/// mindestens 25 m auseinander. Wer nur quert, hört nichts. Je Trail und
/// Fahrt einmal.
class FreeVoiceWatcher {
  FreeVoiceWatcher({this.selfId});

  final String? selfId;
  final _said = <String>{};
  RidePoint? _previous;

  VoiceCue? update(
    RidePoint current,
    List<VoiceTrail> trails, {
    required DateTime now,
  }) {
    final previous = _previous;
    _previous = current;
    if (previous == null || trails.isEmpty) return null;
    if (current.accuracyM > kConfirmMaxAccuracyM ||
        previous.accuracyM > kConfirmMaxAccuracyM) {
      return null;
    }
    final a = LatLng(previous.lat, previous.lng);
    final b = LatLng(current.lat, current.lng);
    if (const Distance().as(LengthUnit.Meter, a, b) < kConfirmMinTravelM) {
      return null;
    }
    final here = LatBox.of([a, b]);
    VoiceTrail? best;
    var bestD = double.infinity;
    for (final t in trails) {
      if (_said.contains(t.trailId) || !t.box.near(here, kConfirmNearM)) {
        continue;
      }
      final dA = distanceToLineM(a, t.line);
      final dB = distanceToLineM(b, t.line);
      if (dA == null ||
          dB == null ||
          dA > kConfirmNearM ||
          dB > kConfirmNearM) {
        continue;
      }
      if (dB < bestD) {
        best = t;
        bestD = dB;
      }
    }
    if (best == null) return null;
    _said.add(best.trailId);
    return VoiceCue(
      VoiceCueKind.trailStart,
      name: best.name,
      grade: best.grade,
      note: voiceNoteFresh(best.note, now: now, selfId: selfId)
          ? best.note
          : null,
    );
  }
}

/// Der Satz zu einer Ansage — kurz, für das Ohr: keine Klammern, keine
/// Pfeile, Zahlen so, wie die Stimme sie liest.
String voiceCueText(AppLocalizations l, VoiceCue cue, {required DateTime now}) {
  String trail() => [
    l.voiceTrailName(
      cue.name?.trim().isNotEmpty == true
          ? cue.name!.trim()
          : l.voiceTrailUnnamed,
    ),
    if (cue.grade != null) gradeLabel(cue.grade!),
  ].join(', ');
  final note = cue.note;
  final noteText = note == null ? null : voiceNoteText(l, note, now: now);
  return switch (cue.kind) {
    VoiceCueKind.offRoute => l.voiceOffRoute,
    VoiceCueKind.backOnRoute => l.voiceBackOnRoute,
    VoiceCueKind.arrived => l.voiceArrived,
    VoiceCueKind.trailAhead => _sentences([
      '${trail()}, ${l.voiceInMeters(voiceRoundMeters(cue.inM ?? kVoiceAheadM))}',
      ?noteText,
    ]),
    VoiceCueKind.trailStart => _sentences([trail(), ?noteText]),
    VoiceCueKind.trailDone => _sentences([
      [
        l.voiceTrailDone(
          cue.name?.trim().isNotEmpty == true
              ? cue.name!.trim()
              : l.voiceTrailUnnamed,
        ),
        if (cue.duration != null) voiceDurationText(l, cue.duration!),
      ].join(', '),
      if (cue.values case final v? when v.jumps > 0) voiceAirText(l, v),
    ]),
  };
}

/// Mehrere Ansagen eines Takts als EIN Satz für die Stimme.
String voiceCuesText(
  AppLocalizations l,
  List<VoiceCue> cues, {
  required DateTime now,
}) => [for (final c in cues) voiceCueText(l, c, now: now)].join(' ');

String _sentences(List<String> parts) => [
  for (final p in parts)
    if (p.trim().isNotEmpty) p.trim().endsWith('.') ? p.trim() : '${p.trim()}.',
].join(' ');

/// „200", „150" — auf 50 m gerundet, nie unter 50.
int voiceRoundMeters(double m) {
  final r = (m / 50).round() * 50;
  return r < 50 ? 50 : r;
}

/// „Max, vor drei Tagen: Baum quer".
String voiceNoteText(
  AppLocalizations l,
  NavNote note, {
  required DateTime now,
}) {
  final days = DateTime(now.year, now.month, now.day)
      .difference(
        DateTime(
          note.createdAt.toLocal().year,
          note.createdAt.toLocal().month,
          note.createdAt.toLocal().day,
        ),
      )
      .inDays;
  final ago = days <= 0
      ? l.voiceToday
      : days == 1
      ? l.voiceYesterday
      : l.voiceDaysAgo(days);
  final author = note.author?.trim().isNotEmpty == true
      ? note.author!.trim()
      : l.voiceNoteBuddy;
  return l.voiceNote(author, ago, note.body.trim());
}

/// „3 Minuten 12" oder „48 Sekunden".
String voiceDurationText(AppLocalizations l, Duration d) {
  final s = d.inSeconds;
  if (s < 60) return l.voiceSeconds(s);
  return l.voiceMinutes(s ~/ 60, s % 60);
}

/// „Airtime 2,4 Sekunden, 3 Sprünge".
String voiceAirText(AppLocalizations l, TrailValues v) =>
    l.voiceAir(NumberFormat('0.0', l.localeName).format(v.airS), v.jumps);
