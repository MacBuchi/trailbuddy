// Suchen, Filtern und Sortieren der Trail-Liste (#66), ohne Widgets —
// der Reiter „Trails" zeigt nur, was hier gerechnet wird. Keine eigene
// Abfrage: alles aus `trailsProvider`, also auch ohne Empfang und mit dem
// Ausgangskorb.
//
// **Der Filter gilt für Liste UND Karte** (seit 0.33.0, Betreiber
// 2026-09-29): EIN Provider, EINE Regel ([passesTrailFilter]). Suche und
// Sortierung bleiben in der Liste — wer „Hexentanz" sucht, will ihn
// finden, nicht die Karte leeren. Ein aktiver Filter meldet sich auf der
// Karte (PilzBuddy #154: eine Karte, die still ausblendet, sieht aus, als
// fehlten Trails).
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/search_text.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart' show MapViewBounds;
import 'still_valid.dart';
import 'trail_condition.dart' show trailConditionLabel;

/// Wessen Trails.
enum TrailOwnerFilter {
  all('Alle'),
  mine('Meine'),
  buddies('Von Buddys');

  const TrailOwnerFilter(this.label);
  final String label;
}

enum TrailSort {
  /// Jüngster Beleg, Beitrag, Hinweis oder Meldung zuerst.
  recent('Zuletzt aktiv'),
  name('Name'),
  length('Länge'),
  descent('Abfahrt (Hm)'),

  /// Leicht zuerst; ohne Einschätzung ans Ende.
  grade('Schwierigkeit'),

  /// Beste Bewertung zuerst (#101, Rework 3.1: „Sortieren nach … in der
  /// eigenen Liste: ja"); ohne Bewertung ans Ende. Nur die Sicht aus
  /// dem eigenen Netz — eine Rangliste darüber hinaus gibt es nie.
  rating('Bewertung');

  const TrailSort(this.label);
  final String label;
}

/// Die Grenzen der Singletrail-Skala, S0 bis S5 — der Bereich, den der
/// Filter ohne Einschränkung abdeckt.
const kMinGrade = 0;
const kMaxGrade = 5;

@immutable
class TrailListFilter {
  const TrailListFilter({
    this.owner = TrailOwnerFilter.all,
    this.minGrade = kMinGrade,
    this.maxGrade = kMaxGrade,
    this.freshNotesOnly = false,
    this.reportedOnly = false,
    this.ratingOpenOnly = false,
    this.stillValidOnly = false,
    this.traits = const {},
  });

  final TrailOwnerFilter owner;

  /// Der S-Grad-Bereich (#222, vorher fest „bis S2"), beide Enden
  /// eingeschlossen. Ist er enger als S0–S5, fällt ein Trail OHNE
  /// Einschätzung heraus: Der Filter verspricht einen Grad, und über einen
  /// Trail, den niemand eingeschätzt hat, weiß die App das nicht. Im
  /// Zweifel die Warnung, wie beim Median ([Trail.grade]). Wie viele es
  /// trifft, sagt die Liste.
  final int minGrade;
  final int maxGrade;

  bool get gradeActive => minGrade > kMinGrade || maxGrade < kMaxGrade;

  /// Der Bereich in Worten: „bis S2", „ab S3", „S1–S3", „nur S2" — und
  /// „S0–S5", wenn er nichts einschränkt.
  String get gradeText {
    if (minGrade == maxGrade) return 'nur ${gradeLabel(minGrade)}';
    if (minGrade == kMinGrade && maxGrade < kMaxGrade) return 'bis ${gradeLabel(maxGrade)}';
    if (maxGrade == kMaxGrade && minGrade > kMinGrade) return 'ab ${gradeLabel(minGrade)}';
    return '${gradeLabel(minGrade)}–${gradeLabel(maxGrade)}';
  }

  /// Nur Trails mit einem neuen Hinweis eines Buddys (#7).
  final bool freshNotesOnly;

  /// Nur gemeldete (gesperrt, zerstört … — [TrailStatus.warns]).
  final bool reportedOnly;

  /// Nur eigene Trails ohne eigene Bewertung (Rework E13) — dieselbe
  /// Regel wie die verblassten Sterne ([Trail.ratingOpen]).
  final bool ratingOpenOnly;

  /// Nur Trails mit einer offenen Frage „Noch gültig?" (#119) — dieselbe
  /// Regel wie die Seite im Profil ([stillValidQuestionsOf]).
  final bool stillValidOnly;

  /// Nur Trails, deren Charakter (#72) ALLE diese Merkmale zeigt — gezählt
  /// wird, was Liste und Blatt zeigen ([Trail.topTraits]), nicht jede
  /// einzelne Nennung: Sonst fände „Flowig" einen Trail, den neun von
  /// zehn Buddys verblockt nennen.
  final Set<TrailTrait> traits;

  bool get isActive =>
      owner != TrailOwnerFilter.all ||
      gradeActive ||
      freshNotesOnly ||
      reportedOnly ||
      ratingOpenOnly ||
      stillValidOnly ||
      traits.isNotEmpty;

  /// Was gefiltert ist, in Worten — für die Zeile auf der Karte.
  String describe() => [
        if (owner != TrailOwnerFilter.all) owner.label,
        if (gradeActive) gradeText,
        if (freshNotesOnly) 'neuer Hinweis',
        if (reportedOnly) 'gemeldet',
        if (ratingOpenOnly) 'Bewertung offen',
        if (stillValidOnly) 'noch gültig?',
        for (final t in TrailTrait.values)
          if (traits.contains(t)) t.label,
      ].join(' · ');

  TrailListFilter copyWith({
    TrailOwnerFilter? owner,
    int? minGrade,
    int? maxGrade,
    bool? freshNotesOnly,
    bool? reportedOnly,
    bool? ratingOpenOnly,
    bool? stillValidOnly,
    Set<TrailTrait>? traits,
  }) =>
      TrailListFilter(
        owner: owner ?? this.owner,
        minGrade: minGrade ?? this.minGrade,
        maxGrade: maxGrade ?? this.maxGrade,
        freshNotesOnly: freshNotesOnly ?? this.freshNotesOnly,
        reportedOnly: reportedOnly ?? this.reportedOnly,
        ratingOpenOnly: ratingOpenOnly ?? this.ratingOpenOnly,
        stillValidOnly: stillValidOnly ?? this.stillValidOnly,
        traits: traits ?? this.traits,
      );

  @override
  bool operator ==(Object other) =>
      other is TrailListFilter &&
      other.owner == owner &&
      other.minGrade == minGrade &&
      other.maxGrade == maxGrade &&
      other.freshNotesOnly == freshNotesOnly &&
      other.reportedOnly == reportedOnly &&
      other.ratingOpenOnly == ratingOpenOnly &&
      other.stillValidOnly == stillValidOnly &&
      setEquals(other.traits, traits);

  @override
  int get hashCode => Object.hash(owner, minGrade, maxGrade, freshNotesOnly, reportedOnly,
      ratingOpenOnly, stillValidOnly, Object.hashAllUnordered(traits));
}

/// Was die Liste zeigt.
typedef TrailListResult = ({
  List<Trail> trails,

  /// Kein Teiltreffer — [trails] sind die nächsten Namen per Tippfehler-
  /// Ausgleich. Die Oberfläche MUSS das sagen („Meintest du …?"): Ein
  /// geratener Treffer, der aussieht wie ein gefundener, ist eine
  /// Behauptung über die Eingabe.
  bool isGuess,

  /// Wie viele der Grad-Bereich nur deshalb verdeckt, weil niemand sie
  /// eingeschätzt hat.
  int hiddenUngraded,
});

/// Die Texte, in denen gesucht wird: der angezeigte Name, die anderen
/// Namen („auch: …") und wer von meinen Buddys ihn beigetragen hat. Kein
/// Hinweistext und keine Beschreibung — dort stünde „Baum liegt quer" als
/// Treffer für „Baum", und die Suche fände Trails über Sätze statt über
/// Namen.
List<String> trailSearchTexts(Trail t) => [
      t.displayName,
      ...t.otherNames,
      for (final d in t.details)
        if (d.userId != t.myId && d.username != null) d.username!,
    ];

/// Wann zuletzt etwas an diesem Trail passiert ist, das ich sehen kann.
DateTime lastActivity(Trail t) {
  var latest = DateTime.fromMillisecondsSinceEpoch(0);
  void take(DateTime? d) {
    if (d != null && d.isAfter(latest)) latest = d;
  }

  for (final r in t.recordings) {
    take(r.createdAt);
  }
  for (final d in t.details) {
    take(d.updatedAt);
  }
  for (final n in t.notes) {
    take(n.createdAt);
  }
  for (final r in t.reports) {
    take(r.reportedAt);
  }
  return latest;
}

/// Lässt [filter] diesen Trail durch? Die EINE Regel für Liste und Karte.
bool passesTrailFilter(Trail t, TrailListFilter filter,
    {Set<String> seenNotes = const {}, DateTime? now, Map<String, DateTime> snoozed = const {}}) {
  if (filter.owner == TrailOwnerFilter.mine && !t.isOwn) return false;
  if (filter.owner == TrailOwnerFilter.buddies && t.isOwn) return false;
  if (filter.freshNotesOnly && !t.hasFreshNote(now: now, seen: seenNotes)) return false;
  if (filter.reportedOnly && !t.status.warns) return false;
  if (filter.ratingOpenOnly && !t.ratingOpen) return false;
  if (filter.stillValidOnly &&
      stillValidQuestionsOf(t, now: now ?? DateTime.now(), snoozed: snoozed).isEmpty) {
    return false;
  }
  if (filter.traits.isNotEmpty && !t.topTraits.toSet().containsAll(filter.traits)) return false;
  if (filter.gradeActive) {
    final g = t.grade;
    if (g == null || g < filter.minGrade || g > filter.maxGrade) return false;
  }
  return true;
}

/// Fällt [t] NUR deshalb heraus, weil der Grad-Bereich eingeschränkt ist
/// und niemand ihn eingeschätzt hat? Die Liste zählt diese, damit der
/// Filter nicht stumm verschluckt, was die App bloß nicht weiß.
bool hiddenOnlyForMissingGrade(Trail t, TrailListFilter filter,
        {Set<String> seenNotes = const {}, DateTime? now, Map<String, DateTime> snoozed = const {}}) =>
    filter.gradeActive &&
    t.grade == null &&
    passesTrailFilter(t, filter.copyWith(minGrade: kMinGrade, maxGrade: kMaxGrade),
        seenNotes: seenNotes, now: now, snoozed: snoozed);

/// Liegt ein Stück von [t] im Ausschnitt [b]? Ein Punkt darin genügt —
/// oder eine Strecke, die ihn quert: Eine vereinfachte Linie hat lange
/// gerade Stücke, und wer hineinzoomt, sieht oft nur deren Mitte.
bool trailInBounds(Trail t, MapViewBounds b) {
  final pts = t.points;
  if (pts.isEmpty) return false;
  if (pts.any(b.contains)) return true;
  for (var i = 1; i < pts.length; i++) {
    if (_segmentCrosses(pts[i - 1], pts[i], b)) return true;
  }
  return false;
}

/// Liang-Barsky in Grad — für einen Bildschirmausschnitt genau genug.
bool _segmentCrosses(LatLng a, LatLng c, MapViewBounds b) {
  final dx = c.longitude - a.longitude, dy = c.latitude - a.latitude;
  var t0 = 0.0, t1 = 1.0;
  for (final (p, q) in [
    (-dx, a.longitude - b.west),
    (dx, b.east - a.longitude),
    (-dy, a.latitude - b.south),
    (dy, b.north - a.latitude),
  ]) {
    if (p == 0) {
      if (q < 0) return false;
      continue;
    }
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
  }
  return true;
}

/// Filtern, suchen, sortieren — in dieser Reihenfolge. Die Suche läuft
/// über das, was die Filter übrig lassen, damit „Meintest du …?" nie
/// einen Trail vorschlägt, den die Chips gerade ausblenden.
///
/// [onMap] ist der Ausschnitt der Karte, wenn „Auf der Karte" an ist
/// (#222) — nur für die Liste, deshalb nicht in [TrailListFilter]: Auf
/// der Karte selbst hieße er „zeige, was du zeigst". Was außerhalb liegt,
/// zählt auch nicht zu den Ungeschätzten.
TrailListResult trailListOf(
  List<Trail> trails, {
  String query = '',
  MapViewBounds? onMap,
  TrailListFilter filter = const TrailListFilter(),
  TrailSort sort = TrailSort.recent,
  Set<String> seenNotes = const {},
  DateTime? now,
  Map<String, DateTime> snoozed = const {},
}) {
  var hiddenUngraded = 0;
  final candidates = <Trail>[];
  for (final t in trails) {
    if (onMap != null && !trailInBounds(t, onMap)) continue;
    if (passesTrailFilter(t, filter, seenNotes: seenNotes, now: now, snoozed: snoozed)) {
      candidates.add(t);
    } else if (hiddenOnlyForMissingGrade(t, filter,
        seenNotes: seenNotes, now: now, snoozed: snoozed)) {
      hiddenUngraded++;
    }
  }

  var isGuess = false;
  var found = candidates;
  final needle = foldSearchText(query);
  if (needle.isNotEmpty) {
    found = [
      for (final t in candidates)
        if (trailSearchTexts(t).any((s) => foldSearchText(s).contains(needle))) t,
    ];
    if (found.isEmpty) {
      isGuess = true;
      found = _closest(candidates, needle);
    }
  }
  return (trails: sortTrails(found, sort), isGuess: isGuess, hiddenUngraded: hiddenUngraded);
}

/// Der Tippfehler-Ausgleich: nur der GERINGSTE gefundene Abstand — wer
/// „Roskopf" tippt, will den Roßkopf sehen und nicht dahinter alles, was
/// zufällig auch in die Nähe passt.
List<Trail> _closest(List<Trail> candidates, String needle) {
  final tolerance = searchTypoTolerance(needle.length);
  if (tolerance < 0) return const [];
  final distances = <Trail, int>{};
  for (final t in candidates) {
    for (final s in trailSearchTexts(t)) {
      final d = nearContainsDistance(needle, foldSearchText(s));
      if (d > tolerance) continue;
      final best = distances[t];
      if (best == null || d < best) distances[t] = d;
    }
  }
  if (distances.isEmpty) return const [];
  final closest = distances.values.reduce((a, b) => a < b ? a : b);
  return [
    for (final e in distances.entries)
      if (e.value == closest) e.key,
  ];
}

/// Sortiert; bei Gleichstand nach Name, damit die Liste nicht springt.
List<Trail> sortTrails(List<Trail> trails, TrailSort sort) {
  int byName(Trail a, Trail b) =>
      foldSearchText(a.displayName).compareTo(foldSearchText(b.displayName));
  // Fehlende Werte (keine Höhen, keine Einschätzung) immer ans Ende,
  // gleich in welche Richtung sortiert wird.
  int nullsLast<T extends Comparable<T>>(T? a, T? b, {bool descending = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  final Comparator<Trail> primary = switch (sort) {
    TrailSort.recent => (a, b) => lastActivity(b).compareTo(lastActivity(a)),
    TrailSort.name => (a, b) => 0,
    TrailSort.length => (a, b) => b.lengthM.compareTo(a.lengthM),
    TrailSort.descent => (a, b) =>
        nullsLast(a.elevation?.lossM, b.elevation?.lossM, descending: true),
    TrailSort.grade => (a, b) => nullsLast(a.grade, b.grade),
    TrailSort.rating => (a, b) => nullsLast(a.rating, b.rating, descending: true),
  };
  return List.of(trails)
    ..sort((a, b) {
      final c = primary(a, b);
      return c != 0 ? c : byName(a, b);
    });
}

/// Welche Art Wort eine Zeile trägt — die Farbe wählt die Oberfläche.
/// [unconfirmed] ist eine Meldung „zu bestätigen" (#101), gedämpft;
/// [condition] der Zustand 1–2 als Wort — ohne eigene Farbe, die gehört
/// der Schwierigkeit (Rework E9).
enum TrailRowTagKind { pending, failure, warning, unconfirmed, note, condition, mine, buddy }

/// Ab diesem Zustand (und schlechter) steht er als Wort in der Liste
/// (Rework E9: „ABGEROCKT", „KAUM FAHRBAR").
const kConditionWordMax = 2;

/// Die Wörter einer Zeile der Liste (Design 1j): rechts vom Farbstreifen
/// sagt ein Wort in der Farbe, was los ist. **Ein Zustand schlägt die
/// Beziehung** — ein wartender, gemeldeter oder neu kommentierter Trail
/// nennt das; nur wenn nichts los ist, steht dort, wem er gehört („MEIN ·
/// 2 BUDDYS", „JAN, MIRA"). Die Beziehung sagt ohnehin schon der Streifen,
/// das Wort gibt sie Bildschirmlesern und allen, die Farben schlecht
/// trennen.
///
/// [nameOf] löst einen Buddy auf (Alias vor Name, `BuddyNames.of`).
List<({String text, TrailRowTagKind kind})> trailRowTags(
  Trail t, {
  required bool freshNote,
  required String Function(String userId, String? username) nameOf,
}) {
  if (t.pending) {
    final failure = t.pendingFailure;
    return [
      failure == null
          ? (text: 'WARTET AUF ÜBERTRAGUNG', kind: TrailRowTagKind.pending)
          // Eine Ablehnung ist ein Satz, kein Etikett — nicht in Versalien.
          : (text: failure, kind: TrailRowTagKind.failure),
    ];
  }
  final unconfirmed = t.shownStatus.unconfirmed?.status;
  final condition = t.shownCondition.confirmed?.condition;
  final tags = <({String text, TrailRowTagKind kind})>[
    if (t.pendingDetails)
      (
        text: t.sendingDetails ? 'BEITRAG WIRD ÜBERTRAGEN' : 'BEITRAG WARTET AUF ÜBERTRAGUNG',
        kind: TrailRowTagKind.pending
      ),
    if (t.status.warns) (text: t.status.label.toUpperCase(), kind: TrailRowTagKind.warning),
    // Eine jüngere unbestätigte Meldung, die etwas anderes sagt als die
    // bestätigte: gedämpft, mit Fragezeichen („GESPERRT?").
    if (unconfirmed != null && unconfirmed != t.status)
      (text: '${unconfirmed.label.toUpperCase()}?', kind: TrailRowTagKind.unconfirmed),
    if (freshNote) (text: 'NEUER HINWEIS', kind: TrailRowTagKind.note),
    // Der Zustand hinter Meldung und Hinweis, nur wenn er schlecht ist —
    // „Gut" in jeder Zeile wäre Lärm.
    if (condition != null && condition <= kConditionWordMax)
      (text: trailConditionLabel(condition).toUpperCase(), kind: TrailRowTagKind.condition),
  ];
  if (tags.isNotEmpty) return tags;

  final buddies = [
    for (final id in t.buddyIds)
      nameOf(id, t.details.where((d) => d.userId == id && d.username != null).firstOrNull?.username),
  ];
  if (t.isOwn) {
    final n = buddies.length;
    return [
      (
        text: n == 0 ? 'MEIN' : 'MEIN · $n ${n == 1 ? 'BUDDY' : 'BUDDYS'}',
        kind: TrailRowTagKind.mine,
      ),
    ];
  }
  if (buddies.isEmpty) return const [];
  final shown = buddies.take(2).join(', ').toUpperCase();
  return [
    (
      text: buddies.length > 2 ? '$shown +${buddies.length - 2}' : shown,
      kind: TrailRowTagKind.buddy,
    ),
  ];
}
