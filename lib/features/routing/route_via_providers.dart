// Die Naht der Zwischenpunkte (#234) zwischen Karte und Ergebnis-Blatt.
// Die KARTE ändert die Punkte (Tipp auf die Linie, Ziehen, Tipp auf den
// Punkt), der BESITZER rechnet — das Blatt „Route" oder der Planer. Er
// hört auf diesen Zustand und rechnet neu, sobald die Punkte andere sind
// als die, mit denen er zuletzt gerechnet hat. Geht es nicht (kein Weg
// durch den Punkt), stellt er die alten zurück ([RouteViaNotifier.reject])
// und die Karte sagt es.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'route_vias.dart';

/// Wer die Punkte gerade gelten lässt.
enum ViaOwner { route, loop }

class ViaEdit {
  const ViaEdit(this.owner, this.vias, {this.rejections = 0});

  final ViaOwner owner;
  final RouteVias vias;

  /// Zählt die abgelehnten Änderungen — die Karte meldet jede neue.
  final int rejections;

  ViaEdit withVias(RouteVias v) => ViaEdit(owner, v, rejections: rejections);
}

class RouteViaNotifier extends Notifier<ViaEdit?> {
  @override
  ViaEdit? build() => null;

  /// Ein Ergebnis liegt auf der Karte: Punkte sind ab jetzt möglich —
  /// mit [vias], wenn das Ergebnis schon welche hat.
  void begin(ViaOwner owner, [RouteVias vias = RouteVias.none]) => state = ViaEdit(owner, vias);

  /// Nur der Besitzer beendet.
  void end(ViaOwner owner) {
    if (state?.owner == owner) state = null;
  }

  /// Ein Tipp auf die Linie: ein neuer Punkt im getroffenen Teilstück.
  void insert(RouteLegHit hit, LatLng p) {
    final s = state;
    if (s == null) return;
    state = s.withVias(s.vias.insert(hit.leg, p, hit.line).$1);
  }

  void move(ViaRef ref, LatLng p) {
    final s = state;
    if (s != null) state = s.withVias(s.vias.move(ref, p));
  }

  void remove(ViaRef ref) {
    final s = state;
    if (s != null) state = s.withVias(s.vias.remove(ref));
  }

  /// Alle Punkte auf einmal (Rückgängig, Zurücksetzen).
  void set(RouteVias vias) {
    final s = state;
    if (s != null) state = s.withVias(vias);
  }

  /// Der Besitzer konnte mit den neuen Punkten nicht rechnen: die alten
  /// zurück, und die Karte sagt es.
  void reject(RouteVias previous) {
    final s = state;
    if (s != null) state = ViaEdit(s.owner, previous, rejections: s.rejections + 1);
  }
}

final routeViaProvider = NotifierProvider<RouteViaNotifier, ViaEdit?>(RouteViaNotifier.new);
