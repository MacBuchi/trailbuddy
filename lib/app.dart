import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_colors.dart';
import 'core/app_theme.dart';
import 'core/router.dart';
import 'core/widgets/preview_ribbon.dart';
import 'core/widgets/push_listener.dart';
import 'core/widgets/start_splash.dart';
import 'core/widgets/update_gate.dart';
import 'features/coach/coach.dart';
import 'l10n/l10n.dart';

class TrailBuddyApp extends ConsumerWidget {
  const TrailBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TrailBuddy',
      routerConfig: router,
      // UpdateGate innen: ist die App zu alt, ersetzt er den Router-Inhalt
      // komplett. PushListener darüber: Eine Meldung kann eintreffen,
      // während jemand im Profil oder in der Buddy-Liste steht, nicht nur
      // auf der Karte — und im Vordergrund zeigt Android sie nicht selbst
      // an (#34). PreviewRibbon ganz außen: Der Hinweis, dass dies ein
      // Entwicklungsstand ist, gilt auch über der Update-Sperre — gerade
      // dort, wo sonst nichts von der App zu sehen ist. Im normalen Build
      // reicht er nur durch.
      // StartSplash über allem (1p): Er liegt nur beim Start einmal
      // darüber, die App lädt darunter schon.
      //
      // Die Hinweis-Maschine (#132) liegt UNTER dem Splash und über allem
      // anderen, auch über Dialogen und Blättern — nur so kann sie in der
      // Werkzeugleiste und im Filter-Blatt hervorheben. Der Splash bleibt
      // ganz außen: Er schluckt 1,45 s lang Tipps, Hinweis und Startseite
      // darunter sind statisch, nichts geht verloren. Update-Banner und
      // Push-Leiste liegen während einer Tour im Dunkel — hinnehmbar.
      // `CoachSemanticsGate` blendet für TalkBack aus, was darunter liegt.
      builder: (context, child) => StartSplash(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoachSemanticsGate(
              child: PreviewRibbon(
                child: PushListener(
                  child: UpdateGate(child: child ?? const SizedBox.shrink()),
                ),
              ),
            ),
            CoachOverlay(
              onNavigate: (route) => router.push(route),
              backButtonDispatcher: router.backButtonDispatcher,
            ),
          ],
        ),
      ),
      theme: buildAppTheme(AppColors.light),
      darkTheme: buildAppTheme(AppColors.dark),
      themeMode: ref.watch(appearanceProvider),
      // Sprache (#209): vorerst fest Deutsch, siehe [appLocaleProvider].
      // Ist sie offen, entscheidet [resolveAppLocale] über die Liste des
      // Geräts — mit Englisch statt der ersten unterstützten als Rückfall.
      locale: ref.watch(appLocaleProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (preferred, _) =>
          resolveAppLocale(preferred),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      debugShowCheckedModeBanner: false,
    );
  }
}
