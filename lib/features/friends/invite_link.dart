/// Was ein gescannter Einladung-QR in der App öffnet (#496, #502).
///
/// Der QR trägt für alle dieselbe Adresse: die Installationsseite mit dem
/// Namen. Hat das Telefon TrailBuddy, fängt Android diese Adresse ab — der
/// Intent-Filter im Manifest — und die App öffnet die Buddys mit dem Namen
/// in der Suche. Hat es sie nicht, öffnet sich der Browser wie bisher.
library;

import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host und Pfad der Einladung. Dieselben wie in `AppInfo.inviteUrl` und im
/// Manifest; `test/android_manifest_test.dart` hält beide zusammen.
const inviteHost = 'macbuchi.github.io';
const invitePathPrefix = '/trailbuddy/';

/// Der Name aus einem Link, null für alles andere.
///
/// Bewusst nur dieser Host unter diesem Pfad: ein Tipp auf irgendeine andere
/// Seite darf die App nicht öffnen.
String? inviteNameFromLink(Uri? link) {
  // Auch der Intent-Filter im Manifest gilt nur für https.
  if (link == null || link.scheme != 'https' || link.host != inviteHost) return null;
  if (!link.path.startsWith(invitePathPrefix)) return null;
  final name = (link.queryParameters['invite'] ?? '').trim();
  return name.isEmpty ? null : name;
}

/// Die Adresse, mit der die App gestartet wurde.
///
/// Ein Global, weil `main()` sie vor `runApp` liest und zu diesem Zeitpunkt
/// noch kein Container existiert. Der Notifier unten nimmt sie beim ersten
/// Aufbau — Tests setzen ihn direkt.
Uri? launchLink;

/// Die Einladung, die noch auf ihren Buddys-Screen wartet.
///
/// Sie überlebt die Anmeldung: Wer den QR scannt, ist oft noch nicht
/// eingeloggt. `take()` holt sie einmal — sonst füllte bei jedem Besuch der
/// Buddys wieder derselbe Name die Suche.
final inviteProvider = NotifierProvider<InviteNotifier, String?>(InviteNotifier.new);

class InviteNotifier extends Notifier<String?> {
  StreamSubscription<Uri>? _links;

  @override
  String? build() {
    ref.onDispose(() => _links?.cancel());
    // Warmstart: die App läuft schon und jemand scannt den QR — Android
    // meldet die Adresse als neuen Intent. Der Startlink selbst kommt nicht
    // über diesen Strom: Supabase hört schon beim `initialize` zu und der
    // Kanal sendet die Startadresse nur einmal. Deshalb liest `main()` ihn.
    if (kIsWeb || !Platform.isAndroid) return inviteNameFromLink(launchLink);
    _links = AppLinks().uriLinkStream.listen((link) {
      final name = inviteNameFromLink(link);
      if (name != null) state = name;
    });
    return inviteNameFromLink(launchLink);
  }

  String? take() {
    final name = state;
    state = null;
    return name;
  }
}
