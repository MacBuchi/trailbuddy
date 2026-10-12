import '../../l10n/l10n.dart';

/// Der Zustand eines Trails (#101, Rework 3.2 und 9): 5 ist der beste
/// Wert, wie bei der Bewertung — dieselbe Richtung, sonst verwechselt man
/// sie.
///
/// Der Wortlaut BESCHREIBT den Zustand, nie eine Maßnahme: kein „Arbeiten
/// fällig", kein „braucht Pflege" (Konzept 7 schließt Bau-Features und
/// Aufrufe zu Arbeitseinsätzen aus). Unterhalb von 1 beginnt die Meldung
/// („gesperrt", „zerstört") — der Zustand beschreibt einen OFFENEN Trail.
///
/// EINE Quelle für jede Stelle, die einen Zustand zeigt oder abfragt.
class TrailConditionLevel {
  const TrailConditionLevel(this.value);

  final int value;

  /// Das Wort: „Ausgefahren" (#209: aus den ARB-Dateien).
  String label(AppLocalizations l) => switch (value) {
        5 => l.conditionTop,
        4 => l.conditionGood,
        3 => l.conditionWorn,
        2 => l.conditionRough,
        1 => l.conditionBarelyRideable,
        _ => throw StateError('Kein Zustand: $value'),
      };

  /// Ein Satz für Auswahl und Bildschirmleser.
  String description(AppLocalizations l) => switch (value) {
        5 => l.conditionTopDescription,
        4 => l.conditionGoodDescription,
        3 => l.conditionWornDescription,
        2 => l.conditionRoughDescription,
        1 => l.conditionBarelyRideableDescription,
        _ => throw StateError('Kein Zustand: $value'),
      };
}

const kTrailConditions = <TrailConditionLevel>[
  TrailConditionLevel(5),
  TrailConditionLevel(4),
  TrailConditionLevel(3),
  TrailConditionLevel(2),
  TrailConditionLevel(1),
];

TrailConditionLevel trailCondition(int value) =>
    kTrailConditions.firstWhere((c) => c.value == value);

/// Nur das Wort — für den Rechenteil der Liste, der ohne Widgets bleibt.
String trailConditionLabel(AppLocalizations l, int value) => trailCondition(value).label(l);
