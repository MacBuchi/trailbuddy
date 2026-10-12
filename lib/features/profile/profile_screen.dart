import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../core/app_colors.dart';
import '../../core/app_distribution.dart';
import '../../core/app_info.dart';
import '../../core/app_theme.dart';
import '../../core/errors.dart';
import '../../core/update_check.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/info_button.dart';
import '../../core/widgets/letter_avatar.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/password_field.dart';
import '../../core/widgets/safety_note.dart';
import '../../data/providers.dart';
import '../coach/coach.dart';
import '../feedback/feedback_dialog.dart';
import '../help/tab_tours.dart' show ProfileCoach;
import '../highlights/highlight_sheet.dart' show unseenHighlightCountProvider;
import '../friends/friend_providers.dart';
import '../offline_areas/area_providers.dart' show storedAreasProvider;
import '../offline_areas/height_tiles.dart' show kHeightsAttribution;
import '../rides/ride_providers.dart' show rideRecordingAvailableProvider, ridesProvider;
import '../routing/ride_calibration.dart';
import '../routing/ride_calibrator.dart';
import '../routing/route_profile.dart';
import '../trails/merge_proposal_card.dart' show mergeProposalsProvider;
import '../trails/trail_providers.dart' show stillValidQuestionsProvider, trailCacheProvider, trailsProvider;
import 'account_dialogs.dart';
import 'profile_providers.dart';
import 'push_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).valueOrNull;
    final areas = ref.watch(storedAreasProvider).valueOrNull;
    final push = ref.watch(pushEnabledProvider);
    final mode = ref.watch(appearanceProvider);
    final stillValid = ref.watch(stillValidQuestionsProvider).length;
    final proposals = ref.watch(mergeProposalsProvider).length;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            // Nach dem Abmelden leitet der Router sofort auf /login um —
            // alles, was danach noch `ref` bräuchte, gehört VOR diesen
            // Aufruf.
            onPressed: () async {
              // Eine laufende Tour endet mit dem Konto (#135): Ihre Anker
              // verschwinden, und die Überlagerung läge sonst über dem Login.
              ref.read(coachProvider.notifier).finish();
              // Die Kopie des Netzes (#32) gehört dem Konto, nicht dem
              // Gerät — sie geht mit. Der Ausgangskorb bleibt: Er trägt
              // Originale und ist an die Konto-Kennung gebunden.
              await ref.read(trailCacheProvider).clear();
              await ref.read(authRepositoryProvider).signOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CoachAnchor(
        id: ProfileCoach.list,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (profile != null) ...[
            _ProfileHeader(username: profile.username),
            const SizedBox(height: 16),
            Divider(height: 1, color: palette.line),
            const SizedBox(height: 16),
          ] else if (profileAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CenteredTrailLoader(),
            ),
          _ProfileRow(
            id: 'import',
            icon: Icons.file_download_outlined,
            title: 'Trails importieren',
            value: 'GPX aus anderen Apps in dein Netz holen',
            onTap: () => context.push('/profile/import'),
          ),
          _ProfileRow(
            id: 'rides',
            icon: Icons.directions_bike,
            title: 'Meine Fahrten',
            value: 'Liegen nur auf diesem Gerät',
            onTap: () => context.push('/profile/rides'),
          ),
          // #119: eigene Angaben, die älter als 30 Tage sind — nur, wenn
          // es welche gibt; dann sagt der Zähler, wie viele.
          if (stillValid > 0)
            _ProfileRow(
              id: 'still-valid',
              icon: Icons.fact_check_outlined,
              title: 'Noch gültig?',
              value: stillValid == 1 ? '1 Angabe zu prüfen' : '$stillValid Angaben zu prüfen',
              onTap: () => context.push('/profile/still-valid'),
            ),
          // #107: „Sind das dieselben?" — nur, wenn es etwas zu prüfen gibt.
          if (proposals > 0)
            _ProfileRow(
              id: 'merge-proposals',
              icon: Icons.merge_type,
              title: 'Sind das dieselben?',
              value: proposals == 1 ? '1 Paar zu prüfen' : '$proposals Paare zu prüfen',
              onTap: () => context.push('/profile/merge-proposals'),
            ),
          _ProfileRow(
            id: 'areas',
            icon: Icons.map_outlined,
            title: 'Meine Bereiche',
            value: switch (areas?.length) {
              null || 0 => 'Karten für unterwegs',
              final n => 'Karten für unterwegs · $n gespeichert',
            },
            onTap: () => context.push('/profile/areas'),
          ),
          _ProfileRow(
            id: 'notifications',
            icon: Icons.notifications_outlined,
            title: 'Benachrichtigungen',
            value: push ? 'Ein' : 'Aus',
            onTap: () => context.push('/profile/notifications'),
          ),
          _ProfileRow(
            id: 'rider',
            icon: Icons.pedal_bike_outlined,
            title: 'Fahrerprofil',
            value: ref.watch(riderProfileProvider).label(context.l10n),
            onTap: () => context.push('/profile/rider'),
          ),
          _ProfileRow(
            id: 'appearance',
            icon: Icons.contrast,
            title: 'Erscheinungsbild',
            value: switch (mode) {
              ThemeMode.light => 'Hell',
              ThemeMode.dark => 'Dunkel',
              ThemeMode.system => theme.brightness == Brightness.dark
                  ? 'Dunkel · folgt dem System'
                  : 'Hell · folgt dem System',
            },
            onTap: () => context.push('/profile/appearance'),
          ),
          _ProfileRow(
            id: 'account',
            icon: Icons.person_outline,
            title: 'Konto',
            value: 'Name, E-Mail, Passwort, Geräte',
            onTap: () => context.push('/profile/account'),
          ),
          // „Entdecken" (#135): alles, was TrailBuddy kann, mit Neu-Punkt.
          _ProfileRow(
            id: 'discover',
            icon: Icons.lightbulb_outline,
            title: 'Entdecken',
            value: 'Was TrailBuddy kann',
            badge: ref.watch(unseenHighlightCountProvider),
            onTap: () => context.push('/profile/discover'),
          ),
          // Über „Über TrailBuddy" (#131): Wer eine Erklärung sucht, landet
          // hier eher als in den Rechtstexten darunter.
          _ProfileRow(
            id: 'help',
            icon: Icons.help_outline,
            title: 'Kurzanleitung',
            value: 'Das Wichtigste in sechs Schritten',
            onTap: () => context.push('/profile/help'),
          ),
          _ProfileRow(
            id: 'about',
            icon: Icons.info_outline,
            title: 'Über TrailBuddy',
            value: 'Neuigkeiten, Datenschutz, Impressum, Lizenzen',
            onTap: () => context.push('/profile/about'),
          ),
          const SizedBox(height: 24),
          Text(
            '${version == null ? '' : 'v$version · '}'
            'Kartendaten © OpenStreetMap · Protomaps',
            key: const ValueKey('profile-footer'),
            style: AppFonts.numbers(theme.textTheme.bodySmall).copyWith(color: palette.muted),
          ),
        ],
      )),
    );
  }
}

/// Kopf des Profils (Design 1l): Avatar, Name, drei Zahlen — gezählt
/// aus dem, was die App ohnehin geladen hat; eine fehlende Zahl fällt
/// weg, statt als 0 dazustehen.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final trails = ref.watch(trailsProvider).valueOrNull;
    final friendships = ref.watch(friendshipsProvider).valueOrNull;
    final rides = ref.watch(rideRecordingAvailableProvider)
        ? ref.watch(ridesProvider).valueOrNull
        : null;
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final stats = [
      if (trails != null)
        plural(trails.where((t) => t.pending || t.recordings.any((r) => r.userId == uid)).length,
            'Trail', 'Trails'),
      if (friendships != null)
        plural(friendships.where((f) => f.isAccepted).length, 'Buddy', 'Buddys'),
      if (rides != null) plural(rides.length, 'Fahrt', 'Fahrten'),
    ];
    return Row(
      children: [
        LetterAvatar(name: username, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Versalien wie die Titel — der Bildschirmleser bekommt den
              // Namen, wie er geschrieben ist.
              Semantics(
                label: username,
                excludeSemantics: true,
                child: Text(username.toUpperCase(),
                    key: const ValueKey('profile-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (stats.isNotEmpty)
                Text(stats.join(' · '),
                    key: const ValueKey('profile-stats'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Eine Zeile des Profils als Karte: Symbol auf eigener Fläche, Titel,
/// darunter der aktuelle Wert, rechts der Pfeil (Design 1l).
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.badge = 0,
  });

  /// Der Neu-Punkt (#135): wie viele Einträge noch nicht angesehen sind.
  final int badge;
  final String id;
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    // Jede Zeile ist ein Anker der Vorführungen (#135), aus ihrer Kennung.
    return CoachAnchor(
      id: ProfileCoach.row(id),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('profile-$id'),
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: palette.accentText),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(value, style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
                    ],
                  ),
                ),
                if (badge > 0)
                  Container(
                    key: ValueKey('profile-$id-badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$badge',
                        style: AppFonts.numbers(theme.textTheme.labelSmall).copyWith(color: AppColors.onBrand)),
                  ),
                Icon(Icons.chevron_right, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

/// Unterseite des Profils: Titel oben, Inhalt als Liste.
class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(16), children: children),
      );
}

/// „Konto": Name, E-Mail, Passwort, andere Geräte — und ganz unten,
/// abgesetzt, das Löschen.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    return _ProfilePage(title: 'Konto', children: [
      ChangeUsernameTile(username: profile?.username),
      const ChangeEmailTile(),
      const _ChangePasswordTile(),
      const SignOutOtherDevicesTile(),
      const Divider(height: 40),
      _DeleteAccountTile(username: profile?.username),
    ]);
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ProfilePage(title: 'Benachrichtigungen', children: [_PushSection()]);
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ProfilePage(title: 'Erscheinungsbild', children: [_AppearanceSection()]);
}

class RiderProfileScreen extends StatelessWidget {
  const RiderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ProfilePage(title: 'Fahrerprofil', children: [_RiderProfileSection()]);
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ProfilePage(title: 'Über TrailBuddy', children: [_AboutSection()]);
}

/// Passwort ändern für Angemeldete. Der Reset-Flow auf dem Login-Screen
/// hilft nur, wer ausgesperrt ist — wer drin ist, braucht diesen Weg.
class _ChangePasswordTile extends ConsumerWidget {
  const _ChangePasswordTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline),
      title: const Text('Passwort ändern'),
      subtitle: const Text(
          'Braucht dein aktuelles Passwort — so ist ein fremdes Gerät '
          'allein nicht genug'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _ChangePasswordDialog(),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _currentController.text.isNotEmpty &&
      _newController.text.length >= minPasswordLength &&
      _newController.text == _repeatController.text;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dein Passwort ist geändert.')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = changePasswordErrorMessage(e));
    } catch (e, stackTrace) {
      logError('Passwort ändern', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _currentController,
              label: 'Aktuelles Passwort',
              textInputAction: TextInputAction.next,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _newController,
              label: 'Neues Passwort (mind. $minPasswordLength Zeichen)',
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _repeatController,
              label: 'Neues Passwort wiederholen',
              onSubmitted: (_) => (_canSave && !_busy) ? _save() : null,
              onChanged: (_) => setState(() {}),
            ),
            PasswordMatchHint(
              password: _newController.text,
              repeated: _repeatController.text,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormNotice(message: _error!, tone: NoticeTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: (!_canSave || _busy) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Konto endgültig löschen — bewusst ganz unten und optisch abgesetzt.
class _DeleteAccountTile extends ConsumerWidget {
  const _DeleteAccountTile({required this.username});

  final String? username;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final name = username;
    if (name == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _DeleteAccountDialog(username: name),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(trailCacheProvider).clear();
      await ref.read(authRepositoryProvider).deleteAccount();
      // Der Router schickt nach dem Abmelden automatisch auf /login.
    } catch (e, stackTrace) {
      logError('Konto löschen', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.no_accounts_outlined, color: error),
      title: Text('Konto löschen', style: TextStyle(color: error)),
      subtitle: const Text(
          'Entfernt dich und alle deine Trails endgültig — ohne Karenzzeit.'),
      // Ohne geladenes Profil fehlt der Benutzername für die Bestätigung.
      enabled: username != null,
      onTap: () => _confirmAndDelete(context, ref),
    );
  }
}

/// Bestätigung durch Abtippen des Benutzernamens. Ein Ja/Nein-Dialog wäre
/// für eine unwiderrufliche Aktion zu leicht versehentlich zu treffen.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.username});

  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == widget.username;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Konto endgültig löschen?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Sofort und unwiderruflich gelöscht werden: dein Profil, '
                'alle deine Trails und deine Buddy-Verbindungen.'),
            const SizedBox(height: 12),
            const Text(
                'Deine Trails verschwinden damit auch aus dem Netz deiner '
                'Buddys — geteilte Trails sind Kopien deiner Daten, keine '
                'eigenen.'),
            const SizedBox(height: 12),
            Text(
              'Bereits abgeschicktes Feedback bleibt bestehen: es steht mit '
              'deinem Benutzernamen öffentlich im GitHub-Projekt und lässt '
              'sich von hier aus nicht zurückholen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Tippe „${widget.username}" ein, um zu bestätigen:'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Benutzername',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: (!_matches || _busy)
              ? null
              : () {
                  setState(() => _busy = true);
                  Navigator.of(context).pop(true);
                },
          child: const Text('Endgültig löschen'),
        ),
      ],
    );
  }
}

/// „Erscheinungsbild": wie das System, hell oder dunkel. Gerätelokal —
/// das Zweitgerät darf anders aussehen.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            key: const ValueKey('appearance'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System')),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Hell')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dunkel')),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(appearanceProvider.notifier).set(s.single),
          ),
        ),
        const SizedBox(height: 4),
        Text('Gilt nur für dieses Gerät. Die Karte selbst bleibt hell.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Das Fahrerprofil (Konzept-Routing 2.1): Bio-Bike oder E-Bike, mit
/// den Zahlen, die es ändert — und nur denen. Gerätelokal; die
/// Routenplanung liest es, jede Fahrt merkt es sich beim Start.
class _RiderProfileSection extends ConsumerStatefulWidget {
  const _RiderProfileSection();

  @override
  ConsumerState<_RiderProfileSection> createState() => _RiderProfileSectionState();
}

class _RiderProfileSectionState extends ConsumerState<_RiderProfileSection> {
  bool _learning = false;

  /// Aus den eigenen Fahrten lernen (Schritt 6) — auf Knopfdruck, mit
  /// einem Satz danach, der sagt, was gezählt hat.
  Future<void> _learn() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _learning = true);
    LearnResult r;
    try {
      r = await ref.read(riderCalibrationsProvider.notifier).learn();
    } finally {
      if (mounted) setState(() => _learning = false);
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(learnResultText(l10n, r))));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(riderProfileProvider);
    final text = Theme.of(context).textTheme;
    final calibrations = ref.watch(riderCalibrationsProvider);
    final params = ref.watch(calibratedRiderProvider(profile));
    final cal = calibrations.of(profile);
    String learned(double? v) => v == null ? '' : ' (gelernt)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RiderProfile>(
            key: const ValueKey('rider-profile'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: RiderProfile.bio,
                  icon: Icon(Icons.pedal_bike_outlined),
                  label: Text('Bio-Bike')),
              ButtonSegment(
                  value: RiderProfile.ebike,
                  icon: Icon(Icons.electric_bike_outlined),
                  label: Text('E-Bike')),
            ],
            selected: {profile},
            onSelectionChanged: (s) => ref.read(riderProfileProvider.notifier).set(s.single),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Das Profil ändert drei Dinge für die Routenplanung: wie schnell es '
          'bergauf geht, wie teuer ein Wanderweg bergauf ist und die Vorgabe '
          'für die Höhenmeter einer Runde. Bergab bleibt ein S2 ein S2.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Steigrate Forstweg: ${params.climbTrackMPerH.round()} hm/h${learned(cal.climbTrackMPerH)} · Pfad: '
          '${params.climbPathMPerH.round()} hm/h${learned(cal.climbPathMPerH)} · Schieben: '
          '${params.pushRateMPerH.round()} hm/h${learned(cal.pushRateMPerH)}\n'
          'Flach: ${params.vFlatKmh.round()} km/h${learned(cal.vFlatKmh)} · '
          'Wanderweg bergauf: ×${profile.pathUpFactor} · Vorgabe: ${profile.budgetClimbM.round()} hm',
          key: const ValueKey('rider-profile-numbers'),
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Gilt nur für dieses Gerät. Viele fahren beides — umschalten geht jederzeit, '
          'auch im Planer. Jede Fahrt merkt sich das Profil beim Start.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('Aus deinen Fahrten gelernt', style: text.titleMedium),
        const SizedBox(height: 4),
        for (final p in RiderProfile.values)
          Text(
            _calibLine(p, calibrations.of(p)),
            key: ValueKey('rider-calib-${p.name}'),
            style: text.bodySmall,
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(
            key: const ValueKey('rider-learn'),
            onPressed: _learning ? null : _learn,
            icon: _learning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.school_outlined),
            label: const Text('Aus meinen Fahrten lernen'),
          ),
          if (!cal.isEmpty)
            TextButton(
              key: const ValueKey('rider-reset'),
              onPressed: () => ref.read(riderCalibrationsProvider.notifier).reset(profile),
              child: Text('${profile.label(context.l10n)} zurücksetzen'),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Aus Zeit und Höhe deiner Fahrten (Aufzeichnungen und per GPX-Import übernommene): '
          'je Fahrt die Aufstiege ab 100 Höhenmetern '
          'am Stück, eingeordnet über die Wege deiner gespeicherten Bereiche, der Median je '
          'Wegklasse ab drei Aufstiegen. Nie aus Fahrten anderer; nichts verlässt das Gerät.',
          style: text.bodySmall,
        ),
      ],
    );
  }

  /// „Bio-Bike: Forstweg 520 hm/h · flach 14 km/h — aus 14 Fahrten (31
  /// Aufstiege), Stand 1.10.2026" oder „Bio-Bike: Vorgaben".
  String _calibLine(RiderProfile p, RiderCalibration c) {
    if (c.isEmpty) return '${p.label(context.l10n)}: Vorgaben — noch nichts gelernt.';
    final parts = [
      if (c.climbTrackMPerH != null) 'Forstweg ${c.climbTrackMPerH!.round()} hm/h',
      if (c.climbPathMPerH != null) 'Pfad ${c.climbPathMPerH!.round()} hm/h',
      if (c.pushRateMPerH != null) 'Schieben ${c.pushRateMPerH!.round()} hm/h',
      if (c.vFlatKmh != null) 'flach ${c.vFlatKmh!.round()} km/h',
    ];
    final at = c.at?.toLocal();
    final when = at == null ? '' : ', Stand ${at.day}.${at.month}.${at.year}';
    return '${p.label(context.l10n)}: ${parts.join(' · ')} — aus ${c.rides} ${c.rides == 1 ? 'Fahrt' : 'Fahrten'} '
        '(${c.sections} ${c.sections == 1 ? 'Aufstieg' : 'Aufstiege'})$when';
  }
}

/// Benachrichtigungen (#34). Die Systemberechtigung wird ERST hier
/// erfragt, nicht beim Start: Ein Dialog, bevor die Karte auch nur zu
/// sehen war, ist die zuverlässigste Art, ein „Nein für immer" zu
/// bekommen. Der Schalter zeigt das Ergebnis, nicht den Wunsch — wer
/// ablehnt, sieht ihn zurückspringen.
class _PushSection extends ConsumerWidget {
  const _PushSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(pushEnabledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Benachrichtigungen'),
          subtitle: const Text(
              'Wenn ein Buddy zu einem Trail, den du siehst, etwas meldet '
              '(bestätigt, also vor Ort oder gefahren), einen Hinweis '
              'schreibt oder dir eine Nachricht schickt. Gilt nur für '
              'dieses Gerät. In der Benachrichtigung stehen der Trailname, '
              'der Name des Buddys und was er meldet (beim Hinweis und bei '
              'einer Nachricht der Text) — nie ein Ort. Sie läuft über '
              'Google.'),
          value: enabled,
          onChanged: (value) async {
            final problem =
                await ref.read(pushEnabledProvider.notifier).set(value);
            if (!context.mounted || problem == null) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(problem)));
          },
        ),
        if (enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.send_outlined),
            title: const Text('Testnachricht senden'),
            subtitle: const Text(
                'Kommt sie an, funktioniert die ganze Kette bis zu '
                'diesem Gerät.'),
            onTap: () async {
              final problem =
                  await ref.read(pushEnabledProvider.notifier).sendTest();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(problem ?? 'Testnachricht ist unterwegs.')));
            },
          ),
      ],
    );
  }
}

/// „Über TrailBuddy": Version, Update-Status und die öffentlichen Links
/// der App.
class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull ?? '–';
    final updateInfo = ref.watch(updateInfoProvider).valueOrNull;
    final updateStatus = kIsWeb
        ? 'Die Web-App ist immer aktuell.'
        : !AppDistribution.showsUpdateHints
            // Play-Build: der Store aktualisiert selbst, die App prüft nichts.
            ? 'Updates kommen über den Play Store.'
            : updateInfo != null
                ? 'Neueste Version: v${updateInfo.latestVersion} — zum '
                    'Herunterladen auf der Projektseite.'
                : 'Du bist auf dem aktuellen Stand.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Version $version — $updateStatus',
            style: Theme.of(context).textTheme.bodySmall),
        // Nur wo der Update-Weg überhaupt läuft. Im Web und im Play-Build
        // zeigte der Schalter auf nichts; der Provider hält denselben
        // Riegel, hier steht er gegen einen Schalter, den man sonst
        // umlegen könnte, ohne dass je etwas passiert.
        if (updateChecksApply)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Vorabversionen erhalten'),
            subtitle: const Text(
                'Bietet auch Zwischenstände an, die noch nicht freigegeben '
                'sind — ungetestet und häufig. Gilt nur für dieses Gerät.'),
            value: ref.watch(prereleaseUpdatesProvider),
            onChanged: (value) =>
                ref.read(prereleaseUpdatesProvider.notifier).set(value),
          ),
        // Der Web-Gegenpart zu „Vorabversionen erhalten" — aber bewusst
        // KEIN Schalter: Die Vorschau liegt auf einem eigenen Origin, der
        // Wechsel ist also eine Navigation und keine Einstellung. Und weil
        // damit ein eigener `localStorage` gilt, muss der Text die
        // Neuanmeldung ansagen; sonst sieht sie aus wie ein Fehler.
        if (ref.watch(webChannelProvider) == WebChannel.stable)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.science_outlined),
            title: const Text('Entwicklungsversion öffnen'),
            subtitle: const Text(
                'Der neueste Zwischenstand — ungetestet und oft halbfertig. '
                'Öffnet eine eigene Adresse; dort musst du dich neu '
                'anmelden.'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(AppInfo.previewAppUrl),
          ),
        // Und der Rückweg. Er steht nur in der Vorschau, dafür an
        // derselben Stelle — wer hierher gefunden hat, soll auch wieder
        // hinausfinden.
        if (ref.watch(webChannelProvider) == WebChannel.preview)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Zur freigegebenen Version'),
            subtitle: const Text(
                'Du benutzt gerade einen Entwicklungsstand. Die echte App '
                'liegt unter ihrer gewohnten Adresse.'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(AppInfo.webAppUrl),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.lightbulb_outline),
          title: const Text('Idee oder Fehler melden'),
          subtitle: const Text('Wird ein öffentlicher Eintrag auf GitHub'),
          onTap: () => showFeedbackFlow(context, ref),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.auto_stories_outlined),
          title: const Text('Was ist neu'),
          subtitle: const Text('Was sich in welcher Version geändert hat'),
          onTap: () => context.push('/profile/changelog'),
        ),
        // Der Hinweis vom ersten Start, dauerhaft nachlesbar (#131) — als
        // Dialog über `showInfoText`, nicht als eigene Seite: ein Absatz.
        ListTile(
          key: const ValueKey('about-safety-note'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.warning_amber_outlined),
          title: const Text(kSafetyNoteTitle),
          subtitle: const Text('Was TrailBuddy dir nicht abnehmen kann'),
          onTap: () => showInfoText(context, title: kSafetyNoteTitle, text: kSafetyNote),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.code),
          title: const Text('GitHub-Projekt & Dokumentation'),
          subtitle: const Text(AppInfo.githubUrl),
          onTap: () => _open(AppInfo.githubUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.public),
          title: const Text('Web-App'),
          subtitle: const Text(AppInfo.webAppUrl),
          onTap: () => _open(AppInfo.webAppUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Datenschutzerklärung'),
          subtitle: const Text('Was gespeichert wird — und was öffentlich ist'),
          onTap: () => _open(AppInfo.privacyUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.info_outline),
          title: const Text('Impressum'),
          subtitle: const Text('Wer TrailBuddy anbietet'),
          onTap: () => _open(AppInfo.impressumUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-Source-Lizenzen'),
          subtitle: const Text('TrailBuddy steht unter der MIT-Lizenz'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'TrailBuddy',
            applicationVersion: version,
            // Das Pseudonym wie in LICENSE: Der Klarname steht nur, wo er
            // Pflicht ist — Impressum und Datenschutzerklärung.
            applicationLegalese: '© 2026 MacBuchi — MIT-Lizenz',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Kartendaten: © OpenStreetMap-Mitwirkende · Protomaps (ODbL)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Höhendaten gespeicherter Bereiche: $kHeightsAttribution',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
