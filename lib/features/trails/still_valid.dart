// „Noch gültig?" (#119, Rework Abschnitt 9): Meldungen werden nicht still
// weggeräumt — wer gemeldet hat, wird gefragt, ob es noch stimmt. Eine
// Antwort ist eine neue Meldung über `report_trail`; ein Schema braucht
// es nicht (Betreiber, 2026-09-30).
//
// Pur: Trails und Uhr rein, Fragen raus. Kein Netz, keine Provider — die
// Liste, die Karte (Filter) und die Seite im Profil rechnen damit.
import '../../models/trail.dart';

/// Ab diesem Alter wird nach einer eigenen Angabe gefragt.
const kStillValidAfter = Duration(days: 30);

/// „Weiß nicht" lässt eine Angabe so lange in Ruhe (Betreiber,
/// 2026-09-30: 14 Tage). Gemerkt nur auf dem Gerät — eine Tabelle dafür
/// wäre eine Lesequittung, die niemand bestellt hat.
const kStillValidSnooze = Duration(days: 14);

/// Eine Frage: meine Angabe [report] an [trail].
class StillValidQuestion {
  const StillValidQuestion(this.trail, this.report);

  final Trail trail;
  final TrailReport report;

  ReportKind get kind => report.kind;
}

/// Die Fragen zu einem Trail. Gefragt wird nach MEINER jüngsten Angabe je
/// Art, wenn sie
/// - noch angezeigt wird ([Trail.shownStatus]/[Trail.shownCondition]) —
///   hat inzwischen jemand eine jüngere bestätigte abgegeben, ist meine
///   überholt und die Frage sinnlos;
/// - bei einer Meldung warnt (ein altes „offen" schadet niemandem);
/// - älter als [kStillValidAfter] ist und nicht ruht ([snoozed]: Kennung
///   der Angabe → bis wann).
/// Wartende Trails und wartende Angaben fragen nichts: Sie sind gerade
/// erst entstanden.
List<StillValidQuestion> stillValidQuestionsOf(
  Trail t, {
  required DateTime now,
  Map<String, DateTime> snoozed = const {},
}) {
  if (t.pending) return const [];
  final out = <StillValidQuestion>[];
  for (final kind in ReportKind.values) {
    final mine = [
      for (final r in t.reports)
        if (r.kind == kind && r.userId == t.myId) r,
    ]..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    if (mine.isEmpty) continue;
    final r = mine.first;
    if (r.pending) continue;
    final shown = kind == ReportKind.status ? t.shownStatus : t.shownCondition;
    if (!identical(shown.confirmed, r) && !identical(shown.unconfirmed, r)) {
      continue;
    }
    if (kind == ReportKind.status && !(r.status?.warns ?? false)) continue;
    if (now.difference(r.reportedAt) < kStillValidAfter) continue;
    final until = snoozed[r.id];
    if (until != null && now.isBefore(until)) continue;
    out.add(StillValidQuestion(t, r));
  }
  return out;
}

/// Alle Fragen, die älteste Angabe zuerst.
List<StillValidQuestion> stillValidQuestions(
  Iterable<Trail> trails, {
  required DateTime now,
  Map<String, DateTime> snoozed = const {},
}) => [
  for (final t in trails)
    ...stillValidQuestionsOf(t, now: now, snoozed: snoozed),
]..sort((a, b) => a.report.reportedAt.compareTo(b.report.reportedAt));

/// Die ruhenden Angaben aus den Einstellungen: je Eintrag
/// `<Kennung>|<bis, ISO-8601>`. Unlesbares fällt weg.
Map<String, DateTime> decodeStillValidSnoozes(Iterable<String>? raw) => {
  for (final e in raw ?? const <String>[])
    if (e.split('|') case [
      final id,
      final at,
    ] when DateTime.tryParse(at) != null)
      id: DateTime.parse(at).toUtc(),
};

/// Zurück in die Einstellungen — ohne Abgelaufenes, sonst wüchse die
/// Liste mit jeder Antwort weiter.
List<String> encodeStillValidSnoozes(
  Map<String, DateTime> snoozes, {
  required DateTime now,
}) => [
  for (final e in snoozes.entries)
    if (now.isBefore(e.value)) '${e.key}|${e.value.toUtc().toIso8601String()}',
];
