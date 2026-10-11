// Wohin ein Tipp auf eine Benachrichtigung führen darf (#34; PilzBuddy
// #564 als Muster).
//
// **Eine Erlaubnisliste, kein Durchreichen.** Das Ziel reist als
// `data.route` in der Meldung. Die Meldungen erzeugt zwar unsere eigene
// Datenbank (`push_flush`), aber eine Adresse, die von außen
// hereinkommt, bekommt nie ungeprüft den Router: Es gibt genau DREI
// Ziele — einen Trail auf der Karte (`/trail/<uuid>`, der Router setzt
// den Fokus und landet auf der Karte), die Trail-Liste (`/trails`, wenn
// mehrere Trails in einer Meldung stecken) und seit Patch 022 den
// Verlauf mit einem Buddy (`/friends/chat/<uuid>`). Nur diese Formen
// werden angenommen.

final _trailRoute =
    RegExp(r'^/trail/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');

final _chatRoute =
    RegExp(r'^/friends/chat/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');

/// Die Liste — das Ziel, wenn eine Meldung mehrere Trails betrifft.
const kPushTrailsRoute = '/trails';

/// Das Ziel aus einer Meldung — `null`, wenn keines oder ein fremdes.
String? pushRouteOf(Map<String, dynamic> data) {
  final route = data['route'];
  if (route is! String) return null;
  if (route == kPushTrailsRoute ||
      _trailRoute.hasMatch(route) ||
      _chatRoute.hasMatch(route)) {
    return route;
  }
  return null;
}

/// Ist [route] der Verlauf mit einem Buddy (eine Nachricht, #34)?
bool isPushChatRoute(String route) => _chatRoute.hasMatch(route);

/// Die Trail-Kennung aus einem `/trail/<id>`-Ziel, sonst `null`.
String? pushTrailIdOf(String route) =>
    _trailRoute.hasMatch(route) ? route.substring('/trail/'.length) : null;
