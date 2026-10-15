import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
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
  @override
  void initState() {
    super.initState();
    // Was im Ausgangskorb liegt, geht beim Start raus.
    unawaited(ref.read(trailsProvider.notifier).sendOutbox());
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
    return widget.child;
  }
}
