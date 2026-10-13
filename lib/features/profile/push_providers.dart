// Der Push-Schalter dieses Geräts (#34; PilzBuddy #277 als Muster).
//
// **Der Zustand folgt dem ERGEBNIS, nicht dem Wunsch.** Anders als die
// übrigen Schalter im Profil darf dieser nicht sofort umspringen und im
// Hintergrund nachziehen: Beim Einschalten hängt ein Systemdialog
// dazwischen, und wer dort ablehnt, bekommt kein Token. Ein Schalter,
// der dann auf „an" stünde, während nichts registriert ist, wäre eine
// Lüge über den eigenen Zustand — und die teuerste Sorte, weil man sie
// erst merkt, wenn eine erwartete Meldung ausbleibt.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/push_messaging.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';

/// Bekommt dieses Gerät Benachrichtigungen?
///
/// Die Wahrheit steht in `push_devices`; gemerkt wird lokal nur das
/// Token, das zum Austragen gebraucht wird. Ein zweites „an/aus"-Flag
/// liefe beim ersten Abmelden auseinander.
class PushEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).pushToken != null;

  /// Schaltet um und meldet zurück, was daraus geworden ist: `null` bei
  /// Erfolg, sonst ein Satz für die Nutzerin.
  Future<String?> set(AppLocalizations l, bool value) async {
    final settings = ref.read(settingsProvider);
    if (!value) {
      final token = settings.pushToken;
      state = false;
      await settings.setPushToken(null);
      if (token == null) return null;
      try {
        await ref.read(pushRepositoryProvider).unregister(token);
      } catch (e, stackTrace) {
        // Der Schalter steht schon auf „aus", und lokal ist das Token
        // weg — die verwaiste Zeile räumt der Versender beim nächsten
        // „unregistered" von FCM ab. Kein Grund, die Nutzerin mit einem
        // Fehler zu behelligen, den sie nicht beheben kann.
        logError('Push-Gerät austragen', e, stackTrace);
      }
      return null;
    }

    final result = await ref.read(pushTokenProvider)();
    final token = result.token;
    if (token == null) {
      state = false;
      if (result.unavailable) {
        return l.pushUnavailable;
      }
      // **Push ist ein reiner ONLINE-Weg.** Ohne Verbindung gibt es kein
      // Token, und das ist keine Fehlfunktion — aber der Satz muss den
      // richtigen Grund nennen. Wer im Funkloch „nicht erlaubt" liest,
      // sucht in den Android-Einstellungen nach einem Schalter, der dort
      // längst richtig steht.
      if (result.denied) {
        return l.pushDenied;
      }
      return ref.read(noConnectivityProvider)
          ? l.pushOffline
          : l.pushFailed;
    }
    try {
      await ref.read(pushRepositoryProvider).register(token);
    } catch (e, stackTrace) {
      logError('Push-Gerät eintragen', e, stackTrace);
      state = false;
      return friendlyError(l, e);
    }
    await settings.setPushToken(token);
    state = true;
    return null;
  }

  /// „Schick mir einmal eine." Der Beweis, dass die Leitung trägt —
  /// ohne ihn müsste man auf eine echte Meldung eines Buddys warten, um
  /// zu merken, dass etwas klemmt.
  Future<String?> sendTest(AppLocalizations l) async {
    final token = ref.read(settingsProvider).pushToken;
    if (token == null) return l.pushNotRegistered;
    try {
      await ref.read(pushRepositoryProvider).sendTest(token);
      return null;
    } catch (e, stackTrace) {
      logError('Push-Testnachricht', e, stackTrace);
      return friendlyError(l, e);
    }
  }
}

final pushEnabledProvider =
    NotifierProvider<PushEnabledNotifier, bool>(PushEnabledNotifier.new);
