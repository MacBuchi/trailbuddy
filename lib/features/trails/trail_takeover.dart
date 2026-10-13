// Übernehmen beim ersten Befahren (#102, Rework Abschnitt 1 und 9): Wer
// einen Trail fährt, den er bisher nur über Buddys sieht, macht ihn sich
// mit einer Bewertung zu eigen — ein vollständiger eigener Beitrag,
// vorbelegt aus dem, was er sieht. Danach hängt nichts mehr an einem
// fremden Beitrag: Entfreundet der Buddy oder löscht er seinen, steht
// der Trail weiter mit Namen da.
//
// Rein: Trail rein, Vorbelegung raus. Die Voreinstellung IST die Anzeige
// (Betreiber, 2026-09-30): Name, Median-S-Grad, Charakter und
// Median-Sterne der sichtbaren Beiträge — auf dem Gerät gerechnet, nie
// über alle Nutzer (Konzept 12). Ausnahme Zustand: der jüngste
// bestätigte der letzten 90 Tage, sonst nichts.
import '../../models/trail.dart';

/// Wie lange ein bestätigter Zustand als Vorbelegung taugt.
const kTakeOverConditionDays = 90;

/// Die Vorbelegung eines Beitrags beim Übernehmen.
class TakeOver {
  const TakeOver({
    required this.name,
    this.grade,
    this.traits = const {},
    this.rating,
    this.condition,
  });

  /// Leer, wenn der Trail nirgends einen Namen hat.
  final String name;
  final int? grade;
  final Set<TrailTrait> traits;
  final int? rating;
  final int? condition;
}

/// Muss dieser Trail übernommen werden? Genau dann, wenn es noch keinen
/// eigenen Beitrag gibt (Rework Abschnitt 1: „wer ihn schon beschrieben
/// hat, wird nicht noch einmal gefragt"). Wartende Trails haben keine
/// Server-Kennung und damit nichts, woran ein Beitrag hängen könnte.
bool needsTakeOver(Trail t) => !t.pending && t.myDetails == null;

/// Die Voreinstellung aus dem, was ich sehe.
TakeOver takeOverOf(Trail t, {DateTime? now}) {
  final c = t.shownCondition.confirmed;
  final since = (now ?? DateTime.now()).subtract(const Duration(days: kTakeOverConditionDays));
  return TakeOver(
    name: t.name ?? '',
    grade: t.grade,
    traits: t.topTraits.toSet(),
    rating: t.rating,
    condition: c != null && c.reportedAt.isAfter(since) ? c.condition : null,
  );
}

/// Im Blatt „Übernehmen" anbieten (Bestand, #102): Ich habe den Trail
/// belegt, aber mein Beitrag trägt keinen Namen — er hängt also am Namen
/// eines Buddys. Kein Rückfüllen auf dem Server (Konzept 12), der Nutzer
/// übernimmt selbst.
bool offersTakeOver(Trail t) =>
    t.isOwn && !t.pending && !t.pendingDetails && (t.myDetails?.name ?? '').trim().isEmpty;

/// Die eigene Zeile, aufgefüllt mit der Vorbelegung — nur, was dort noch
/// leer ist; was ich schon gesagt habe, bleibt.
TrailDetails takeOverDetails(Trail t, {DateTime? now}) {
  final p = takeOverOf(t, now: now);
  final own = t.myDetails ?? TrailDetails(trailId: t.id, userId: t.myId);
  return own.copyWith(
    name: (own.name ?? '').trim().isEmpty && p.name.isNotEmpty ? p.name : own.name,
    grade: own.grade ?? p.grade,
    traits: own.traits.isEmpty ? p.traits : own.traits,
    rating: own.rating ?? p.rating,
  );
}
