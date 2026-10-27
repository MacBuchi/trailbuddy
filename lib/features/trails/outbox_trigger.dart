import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../data/trail_cache.dart';
import 'trail_providers.dart';

/// Stößt den Ausgangskorb (#30) an: einmal beim Start und bei jeder
/// Rückkehr der Verbindung. Sitzt in der Hülle (`AppShell`), nicht in
/// einem Reiter — bis 0.121.0 hing beides an der Karte, und im Browser,
/// der nach dem Neuladen auf dem Reiter der URL startet, wurde die Karte
/// nie gebaut: Ein Beitrag wartete, bis jemand sie öffnete (gefunden im
/// Browser-Check von 0.102.0, #153).
class OutboxTrigger extends ConsumerStatefulWidget {
  const OutboxTrigger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OutboxTrigger> createState() => _OutboxTriggerState();
}

class _OutboxTriggerState extends ConsumerState<OutboxTrigger> {
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    // Was im Ausgangskorb liegt, geht beim Start raus.
    unawaited(ref.read(trailsProvider.notifier).sendOutbox());
    // Steht die Kopie, wird still neu versucht (#397): Im Wald kommt der
    // Empfang zurück, ohne dass das Gerät den Transportweg wechselt —
    // dann gäbe es keinen Wechsel, der neu lädt, und „Trails vom …"
    // bliebe stehen. Der Takt läuft nur, solange die Kopie steht.
    ref.listenManual<DateTime?>(trailsCachedAtProvider, (_, cachedAt) {
      _retry?.cancel();
      _retry = cachedAt == null
          ? null
          : Timer.periodic(kTrailsCopyRetry, (_) {
              if (!ref.read(noConnectivityProvider)) unawaited(ref.read(trailsProvider.notifier).retryCopy());
            });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Verbindung zurück ⇒ Ausgangskorb losschicken. Genau hier und nicht
    // am App-Resume: Wer aus dem Wald nach Hause kommt, ohne die App zu
    // schließen, hat kein Resume — aber einen Netzwechsel. Steht danach
    // noch die Kopie (#183: Start ohne Empfang), kommt der frische Stand
    // — sonst bliebe „Trails vom …" stehen, bis jemand von Hand neu lädt.
    ref.listen<bool>(noConnectivityProvider, (previous, next) {
      if (previous == true && next == false) {
        unawaited(() async {
          await ref.read(trailsProvider.notifier).sendOutbox();
          if (mounted && ref.read(trailsCachedAtProvider) != null) ref.invalidate(trailsProvider);
        }());
      }
    });
    // Ein anderer Weg ins Netz (Mobilfunk ⇄ WLAN) ist kein Wechsel von
    // „kein Netz", aber vielleicht der Empfang, auf den die Kopie wartet
    // (#397) — nicht auf den nächsten Takt warten.
    ref.listen(connectivityProvider, (previous, next) {
      if (previous?.valueOrNull == null || ref.read(noConnectivityProvider)) return;
      if (previous!.valueOrNull!.every((r) => r == ConnectivityResult.none)) return;
      if (ref.read(trailsCachedAtProvider) != null) unawaited(ref.read(trailsProvider.notifier).retryCopy());
    });
    return widget.child;
  }
}
