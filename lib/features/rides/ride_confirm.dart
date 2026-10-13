// Bestätigen durch Fahren (#116, Rework Abschnitt 9): Wer aufzeichnet und
// auf einen Trail mit UNBESTÄTIGTER Meldung oder unbestätigtem Zustand
// kommt, wird sofort gefragt — über eine lokale Benachrichtigung aus dem
// Service-Isolate. Ohne Netz, und die Position verlässt das Gerät nicht:
// Eine Push vom Server ginge nur, wenn der Server wüsste, wo jemand
// fährt.
//
// Alles hier ist rein: Trails rein, Ziele raus; Ziele und Punkt rein,
// Frage raus; Protokoll rein, Meldungen raus. Kein Netz, keine Platte,
// keine Provider — der Service-Isolate hat keine, und so ist jede Regel
// ohne Gerät geprüft (`test/rides/ride_confirm_test.dart`).
//
// **Eine Bestätigung IST eine Meldung** (Betreiber, 2026-09-30): eine
// bestätigte Meldung des Fahrers mit demselben Wert, über das vorhandene
// `report_trail` mit `on_site`. Kein eigenes Schema: Die Anzeige zeigt
// ohnehin die jüngste bestätigte, und sichtbar ist sie nur im Netz des
// Fahrers (Konzept 12). Eine Fahrt OHNE Antwort bestätigt nichts — wer
// nur ein Stück gefahren ist, sagt nichts über die Meldung eines anderen.
import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../trails/trail_condition.dart';
import 'ride_track.dart';

/// Wie nah ein Fix an der Linie liegen muss: der Korridor des Abgleichs
/// (15 m) plus etwas Luft für GPS unter Bäumen. Enger als „vor Ort"
/// (200 m) mit Absicht — gefragt wird, wer AUF dem Trail fährt, nicht,
/// wer daran vorbeikommt.
const kConfirmNearM = 20.0;

/// Unschärfer als das zählt ein Fix nicht (dieselbe Grenze wie im
/// Zerlege-Blatt): Ein 20-m-Korridor gegen einen ±40-m-Fix ist Rauschen.
const kConfirmMaxAccuracyM = 30.0;

/// Zwei Fixe im Korridor, mindestens so weit auseinander: Wer den Trail
/// nur QUERT, hat einen Fix darauf, nicht zwei in Fahrtrichtung.
const kConfirmMinTravelM = 25.0;

/// Ein Trail, zu dem gefragt werden kann: die angezeigte unbestätigte
/// Meldung und/oder der angezeigte unbestätigte Zustand, dazu die Linie.
/// Die App schreibt die Liste beim Start der Fahrt (und neu, wenn sich
/// die Trails ändern); der Service liest sie — so gilt dieselbe Regel wie
/// in der Anzeige (`shownReportsOf`), ohne dass der Service den ganzen
/// Zwischenspeicher je Takt lesen müsste.
class ConfirmTarget {
  ConfirmTarget({
    required this.trailId,
    required this.name,
    required this.line,
    this.status,
    this.condition,
  }) : box = LatBox.of(line);

  final String trailId;
  final String name;
  final List<LatLng> line;
  final LatBox box;

  /// Die unbestätigte Meldung, wenn eine angezeigt wird.
  final TrailStatus? status;

  /// Der unbestätigte Zustand (1–5), wenn einer angezeigt wird.
  final int? condition;

  Map<String, dynamic> toJson() => {
        'trail': trailId,
        'name': name,
        if (status != null) 'status': status!.db,
        if (condition != null) 'condition': condition,
        'line': [for (final p in line) [p.latitude, p.longitude]],
      };

  static ConfirmTarget? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['trail'];
    final raw = json['line'];
    if (id is! String || raw is! List) return null;
    final line = <LatLng>[
      for (final p in raw)
        if (p is List && p.length == 2 && p[0] is num && p[1] is num)
          LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    final status = json['status'] is String ? TrailStatus.fromDb(json['status'] as String) : null;
    final condition = (json['condition'] as num?)?.toInt();
    if (line.length < 2 || (status == null && condition == null)) return null;
    return ConfirmTarget(
      trailId: id,
      name: json['name'] as String? ?? 'Trail',
      line: line,
      status: status,
      condition: condition != null && condition >= 1 && condition <= 5 ? condition : null,
    );
  }
}

/// Die Trails, zu denen während der Fahrt gefragt wird: alles mit einer
/// angezeigten unbestätigten Meldung oder einem unbestätigten Zustand —
/// auch die eigene („stimmt deine Meldung noch?"). Wartende Trails haben
/// keine Kennung beim Server und fallen weg.
List<ConfirmTarget> confirmTargetsOf(AppLocalizations l, Iterable<Trail> trails) => [
      for (final t in trails)
        if (!t.pending && t.points.length >= 2)
          if (_unconfirmed(t) case (final status, final condition)
              when status != null || condition != null)
            ConfirmTarget(
              trailId: t.id,
              name: t.displayName(l),
              line: t.points,
              status: status,
              condition: condition,
            ),
    ];

(TrailStatus?, int?) _unconfirmed(Trail t) =>
    (t.shownStatus.unconfirmed?.status, t.shownCondition.unconfirmed?.condition);

/// Die Datei, die App und Service teilen. Das Konto steht darin: Die
/// Ziele eines anderen Kontos gehören nicht in eine fremde Fahrt.
String encodeConfirmTargets({required String uid, required List<ConfirmTarget> targets}) =>
    jsonEncode({'uid': uid, 'targets': [for (final t in targets) t.toJson()]});

List<ConfirmTarget> decodeConfirmTargets(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['uid'] != uid) return const [];
    final raw = json['targets'];
    if (raw is! List) return const [];
    return [for (final t in raw) ?ConfirmTarget.fromJson(t)];
  } catch (_) {
    return const [];
  }
}

/// Soll bei [current] gefragt werden — und zu welchem Trail? Beide Fixe
/// ([previous] und [current]) scharf genug, beide im Korridor derselben
/// Linie und mindestens [kConfirmMinTravelM] auseinander. Je Trail und
/// Fahrt höchstens einmal ([asked]); liegen zwei Trails im Korridor, der
/// nähere.
ConfirmTarget? confirmPromptFor({
  required List<ConfirmTarget> targets,
  required RidePoint? previous,
  required RidePoint current,
  required Set<String> asked,
}) {
  if (previous == null) return null;
  if (current.accuracyM > kConfirmMaxAccuracyM || previous.accuracyM > kConfirmMaxAccuracyM) {
    return null;
  }
  final a = LatLng(previous.lat, previous.lng);
  final b = LatLng(current.lat, current.lng);
  if (const Distance().as(LengthUnit.Meter, a, b) < kConfirmMinTravelM) return null;
  final here = LatBox.of([a, b]);
  ConfirmTarget? best;
  var bestD = double.infinity;
  for (final t in targets) {
    if (asked.contains(t.trailId) || !t.box.near(here, kConfirmNearM)) continue;
    final dA = distanceToLineM(a, t.line);
    final dB = distanceToLineM(b, t.line);
    if (dA == null || dB == null || dA > kConfirmNearM || dB > kConfirmNearM) continue;
    if (dB < bestD) {
      best = t;
      bestD = dB;
    }
  }
  return best;
}

/// Die Antworten auf eine Frage. Die Kennungen sind zugleich die der
/// Knöpfe in der Benachrichtigung.
enum ConfirmChoice {
  /// „Stimmt": dieselbe Meldung und derselbe Zustand, bestätigt.
  confirm('confirm'),

  /// „Trail ist frei": die Meldung „offen", bestätigt. Den Zustand lässt
  /// das offen — der steht dann im Zerlege-Blatt noch einmal.
  free('free'),

  /// „Ändern…": öffnet die App; der Wert kommt aus dem Zerlege-Blatt oder
  /// dem Melden am Trail. Selbst schreibt die Antwort nichts.
  change('change');

  const ConfirmChoice(this.id);
  final String id;

  static ConfirmChoice? fromId(String? id) => values.where((c) => c.id == id).firstOrNull;
}

/// Was die Benachrichtigung zeigt. Der Trailname steht darin (Betreiber,
/// 2026-09-30): Sie ist lokal, nichts davon geht über einen Server.
typedef ConfirmNotice = ({String title, String body, List<(ConfirmChoice, String)> actions});

ConfirmNotice confirmNoticeOf(AppLocalizations l, ConfirmTarget t) {
  final parts = <String>[
    if (t.status != null)
      t.status == TrailStatus.open ? l.confirmReportedOpen : l.confirmReportedStatus(t.status!.label(l).toLowerCase()),
    if (t.condition != null) l.confirmCondition(trailConditionLabel(l, t.condition!)),
  ];
  final warns = t.status != null && t.status!.warns;
  return (
    title: t.name,
    body: l.confirmQuestion(_capitalize(parts.join(' · '))),
    actions: [
      (ConfirmChoice.confirm, l.confirmYes),
      if (warns) (ConfirmChoice.free, l.confirmFree),
      (ConfirmChoice.change, l.confirmChange),
    ],
  );
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Eine Zeile im Protokoll der Fahrt: gefragt (mit dem Wert, der da
/// stand — die Ziel-Datei kann sich danach ändern) oder beantwortet.
/// Steht als eigene Zeile in der Fahrt-Datei; `RidePoint.fromJson` lässt
/// sie liegen.
sealed class ConfirmEvent {
  const ConfirmEvent({required this.trailId, required this.at});
  final String trailId;
  final DateTime at;

  Map<String, dynamic> toJson();

  static ConfirmEvent? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '')?.toUtc();
    if (at == null) return null;
    final asked = json['asked'];
    if (asked is String) {
      final status = json['status'] is String ? TrailStatus.fromDb(json['status'] as String) : null;
      final condition = (json['condition'] as num?)?.toInt();
      return ConfirmAsked(
          trailId: asked,
          at: at,
          name: json['name'] as String? ?? 'Trail',
          status: status,
          condition: condition);
    }
    final answered = json['answer'];
    final choice = ConfirmChoice.fromId(json['choice'] as String?);
    if (answered is String && choice != null) {
      return ConfirmAnswered(trailId: answered, at: at, choice: choice);
    }
    return null;
  }

  static bool isEvent(Map<String, dynamic> json) =>
      json.containsKey('asked') || json.containsKey('answer');
}

class ConfirmAsked extends ConfirmEvent {
  const ConfirmAsked({
    required super.trailId,
    required super.at,
    required this.name,
    this.status,
    this.condition,
  });

  ConfirmAsked.of(ConfirmTarget t, {required DateTime at})
      : this(trailId: t.trailId, at: at, name: t.name, status: t.status, condition: t.condition);

  final String name;
  final TrailStatus? status;
  final int? condition;

  @override
  Map<String, dynamic> toJson() => {
        'asked': trailId,
        'name': name,
        if (status != null) 'status': status!.db,
        if (condition != null) 'condition': condition,
        'at': at.toUtc().toIso8601String(),
      };
}

class ConfirmAnswered extends ConfirmEvent {
  const ConfirmAnswered({required super.trailId, required super.at, required this.choice});
  final ConfirmChoice choice;

  @override
  Map<String, dynamic> toJson() => {
        'answer': trailId,
        'choice': choice.id,
        'at': at.toUtc().toIso8601String(),
      };
}

/// Was aus den Antworten einer Fahrt als Meldung hinausgeht — je Trail
/// die LETZTE Antwort, mit der Zeit der Antwort. „Ändern…" und Fragen
/// ohne Antwort schreiben nichts (die fragt das Zerlege-Blatt). Eine
/// Antwort ohne Frage (fremde Zeile) auch nicht: Was bestätigt wird,
/// steht in der Frage.
typedef ConfirmReport = ({String trailId, TrailStatus? status, int? condition, DateTime at});

List<ConfirmReport> confirmReportsOf(Iterable<ConfirmEvent> events) {
  final asked = <String, ConfirmAsked>{};
  final answered = <String, ConfirmAnswered>{};
  for (final e in events) {
    switch (e) {
      case ConfirmAsked():
        asked.putIfAbsent(e.trailId, () => e);
      case ConfirmAnswered():
        final prev = answered[e.trailId];
        if (prev == null || !e.at.isBefore(prev.at)) answered[e.trailId] = e;
    }
  }
  return [
    for (final a in answered.values)
      if (asked[a.trailId] case final q?) ?_reportFor(q, a),
  ];
}

ConfirmReport? _reportFor(ConfirmAsked q, ConfirmAnswered a) => switch (a.choice) {
      ConfirmChoice.confirm when q.status != null || q.condition != null =>
        (trailId: q.trailId, status: q.status, condition: q.condition, at: a.at),
      ConfirmChoice.free => (trailId: q.trailId, status: TrailStatus.open, condition: null, at: a.at),
      _ => null,
    };

/// Die Frage an der Zeile eines wieder gefahrenen Trails im Zerlege-Blatt
/// (#116, zweiter Teil): wer unterwegs nicht geantwortet oder „Ändern…"
/// gewählt hat, bekommt sie hier noch einmal. Nur, was VOR der Fahrt
/// gemeldet war ([rodeAt] = Zeit am Trail) — eine alte Datei bestätigt
/// keine Meldung von gestern. Wer unterwegs geantwortet hat, wird nicht
/// noch einmal gefragt: Seine Meldung ist dann die jüngste bestätigte
/// (auch wartend im Ausgangskorb), und die unbestätigte ist überholt.
ConfirmTarget? splitQuestionFor(AppLocalizations l, Trail trail, DateTime? rodeAt) {
  if (rodeAt == null || trail.pending || trail.points.length < 2) return null;
  bool before(TrailReport? r) => r != null && !r.reportedAt.isAfter(rodeAt);
  final s = trail.shownStatus.unconfirmed;
  final c = trail.shownCondition.unconfirmed;
  final status = before(s) ? s!.status : null;
  final condition = before(c) ? c!.condition : null;
  if (status == null && condition == null) return null;
  return ConfirmTarget(
    trailId: trail.id,
    name: trail.displayName(l),
    line: trail.points,
    status: status,
    condition: condition,
  );
}
