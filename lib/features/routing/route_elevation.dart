// Das Höhenprofil einer geplanten Linie im Ergebnis (#234, Feldwunsch:
// „das Höhenmeterprofil über die Distanz kompakt im unteren Bereich").
// Eine Stelle für das Blatt „Runde" und das Blatt „Zum Trailkopf" /
// „Route hierher": dieselbe Zeichnung wie im Trail-Blatt, kompakt, aus
// dem Geländemodell entlang der Linie (`lineProfileProvider`) — die Engine
// kennt Höhen je Kante, nicht je Punkt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../trails/elevation_profile_chart.dart';
import '../trails/terrain_heights.dart';

class RouteElevationProfile extends ConsumerWidget {
  const RouteElevationProfile(this.points, {super.key});

  /// Die Linie in Fahrtrichtung — dieselbe Liste, die die Karte zeichnet.
  final List<LatLng> points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(lineProfileProvider(points));
    return switch (profile) {
      // Während gelesen wird, steht der Platz schon da — sonst rutschten
      // die Knöpfe darunter, sobald das Profil kommt.
      AsyncLoading() => const SizedBox(height: ElevationProfileChart.compactHeight + 8),
      AsyncData(value: final p?) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ElevationProfileChart(p, compact: true),
        ),
      // Ohne Höhen (eine Kachel fehlt) kein Profil — die Summe sagt dann
      // schon, dass die Höhenmeter eine Untergrenze sind. Ein Lesefehler
      // nimmt nur das Bild weg, nie das Ergebnis.
      _ => const SizedBox.shrink(),
    };
  }
}
