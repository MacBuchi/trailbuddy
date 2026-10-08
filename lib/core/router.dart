import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/providers.dart';
import '../features/coach/coach.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/changelog/changelog_screen.dart';
import '../features/friends/friends_screen.dart';
import '../features/help/help_screen.dart';
import '../features/highlights/discover_screen.dart';
import '../features/help/map_tour.dart' show NavCoach;
import '../features/map/map_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/offline_areas/areas_screen.dart';
import '../features/rides/rides_screen.dart';
import '../features/trails/still_valid_screen.dart';
import '../features/trails/trail_import_screen.dart';
import '../features/trails/trail_providers.dart' show mapFocusTrailProvider;
import '../features/trails/trails_screen.dart';
import 'picture_in_picture.dart';
import 'router_branches.dart';
import 'widgets/keyboard_inset_below_bar.dart';

/// Stößt den Router-Redirect an, sobald sich der Auth-Zustand ändert.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  // `passwordRecovery` bewusst nicht durchlassen: Ein eingelöster
  // Reset-Code erzeugt eine gültige Sitzung, BEVOR das neue Passwort
  // gesetzt ist. Würde der Router darauf reagieren, läge die Karte
  // mitten im Reset offen und die Nutzerin wäre angemeldet, ohne ihr
  // Passwort zu kennen. Der Login-Screen bleibt deshalb stehen, bis
  // `updateUser` das Passwort wirklich geändert hat — dessen
  // `userUpdated`-Ereignis öffnet die App dann (siehe
  // AuthRepository.resetPasswordWithCode).
  final refresh = _AuthRefresh(authRepository.onAuthStateChange
      .where((state) => state.event != AuthChangeEvent.passwordRecovery));
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = authRepository.currentSession != null;
      final onAuthPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      if (!loggedIn) return onAuthPage ? null : '/login';
      if (onAuthPage) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Das Ziel einer Push-Benachrichtigung (#34, `push_routes.dart`):
      // KEINE eigene Seite — der Trail liegt auf der Karte. Die Route
      // stellt den Fokus-Wunsch (die Karte holt ihn beim Aufbau oder
      // sobald der Trail geladen ist) und landet auf der Karte. Als Route
      // statt als Aufruf, weil der Web-Worker die App aus dem Nichts
      // unter `#/trail/<id>` öffnet.
      GoRoute(
          path: '/trail/:id',
          redirect: (context, state) {
            ref.read(mapFocusTrailProvider.notifier).state =
                state.pathParameters['id'];
            return '/';
          }),
      GoRoute(
          path: '/signup', builder: (context, state) => const SignupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const MapScreen()),
          ]),
          // Der Reiter „Trails" steht direkt neben der Karte, weil er
          // dieselben Daten zeigt — nur als Liste.
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/trails',
                builder: (context, state) => const TrailsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/friends',
                builder: (context, state) => const FriendsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                // Unterrouten des Profil-Tabs statt imperativem
                // Navigator.push — die Tab-Leiste bleibt sichtbar, und
                // laufende Vorgänge überleben den Tab-Wechsel.
                routes: [
                  GoRoute(
                      path: 'import',
                      builder: (context, state) => const TrailImportScreen()),
                  GoRoute(
                      path: 'rides',
                      builder: (context, state) => const RidesScreen()),
                  GoRoute(
                      path: 'still-valid',
                      builder: (context, state) => const StillValidScreen()),
                  GoRoute(
                      path: 'areas',
                      builder: (context, state) => const AreasScreen()),
                  GoRoute(
                      path: 'changelog',
                      builder: (context, state) => const ChangelogScreen()),
                  GoRoute(
                      path: 'account',
                      builder: (context, state) => const AccountScreen()),
                  GoRoute(
                      path: 'notifications',
                      builder: (context, state) => const NotificationsScreen()),
                  GoRoute(
                      path: 'rider',
                      builder: (context, state) => const RiderProfileScreen()),
                  GoRoute(
                      path: 'appearance',
                      builder: (context, state) => const AppearanceScreen()),
                  GoRoute(
                      path: 'about',
                      builder: (context, state) => const AboutScreen()),
                  // Die Kurzanleitung (#131). Unter dem Profil, weil sie
                  // dort als Zeile steht; die Leerzustände der anderen
                  // Reiter springen mit `push` hierher.
                  GoRoute(
                      path: 'help',
                      builder: (context, state) => const HelpScreen()),
                  // „Entdecken" (#135): alle Funktionen und Tipps.
                  GoRoute(
                      path: 'discover',
                      builder: (context, state) => const DiscoverScreen()),
                ]),
          ]),
        ],
      ),
    ],
  );
});

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Zurück nach Hierarchie (#175): Blätter, Dialoge und Unterseiten
    // schließt der Navigator ihres Reiters zuerst; an der Wurzel eines
    // anderen Reiters führt Zurück auf die Karte, erst dort verlässt es
    // die App — und das legt sie in den Hintergrund (`popSystemNavigator`
    // in `MainActivity.kt`), statt sie zu beenden. go_router fragt den
    // Navigator des Reiters VOR diesem hier; was dort noch zu schließen
    // ist, kommt also nie bis hierher.
    final onMap = navigationShell.currentIndex == kMapBranchIndex;
    return PopScope(
      canPop: onMap,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(kMapBranchIndex);
      },
      child: Scaffold(
      // Die Tastatur ÜBERLAGERT, sie schiebt nicht (PilzBuddy #397).
      //
      // Ab Werk schrumpft ein Scaffold seinen Body um `viewInsets.bottom`.
      // Hier heißt das: Karte, Knopfspalte UND die Reiterleiste wandern
      // hoch, sobald irgendwo ein Textfeld den Fokus bekommt — obwohl in
      // dieser Hülle gar kein Eingabefeld liegt. Die Felder stecken alle
      // in eigenen Routen (Blätter, Dialoge), und die rechnen ihr
      // `viewInsets` selbst ein; ein Reiter mit eigenem Scaffold weicht
      // weiter aus.
      //
      // Der eigentliche Anlass ist der seltene Fall aus dem Feld: Bleibt
      // das Inset nach dem Schließen der Tastatur stehen, schrumpft der
      // Scaffold WEITER — und was man dann sieht, ist das untere Drittel
      // in `colorScheme.surface`, also weiß. Diese Zeile nimmt dem
      // hängenden Inset die sichtbare Wirkung, und zwar strukturell: Was
      // nicht schrumpft, kann keinen Streifen hinterlassen.
      resizeToAvoidBottomInset: false,
      // Und weil sie nicht ausweicht, liegt ihr Body schon eine
      // Leistenhöhe über dem Rand — ein Reiter-Scaffold darf nur um den
      // Rest der Tastatur schrumpfen.
      body: KeyboardInsetBelowBar(child: navigationShell),
      // Im Bild-im-Bild (#232, 9.6) ist die App nur noch Karte: keine
      // Reiterleiste, die das kleine Fenster zur Hälfte füllte.
      bottomNavigationBar: ref.watch(pipModeProvider) ? null : CoachAnchor(
        id: NavCoach.bar,
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          // Die Anker der Karten-Tour (#132): Sie nennt die Bereiche zum
          // Schluss, der Ring liegt je Bereich.
          destinations: const [
            CoachAnchor(
                id: NavCoach.map,
                child: NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: 'Karte')),
            CoachAnchor(
                id: NavCoach.trails,
                child: NavigationDestination(
                    icon: Icon(Icons.route_outlined),
                    selectedIcon: Icon(Icons.route),
                    label: 'Trails')),
            CoachAnchor(
                id: NavCoach.buddys,
                child: NavigationDestination(
                    icon: Icon(Icons.group_outlined),
                    selectedIcon: Icon(Icons.group),
                    label: 'Buddys')),
            CoachAnchor(
                id: NavCoach.profile,
                child: NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profil')),
          ],
        ),
      ),
    ),
    );
  }
}
