import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
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
    final l = context.l10n;

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
            tooltip: l.profileSignOut,
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
            title: l.profileImportTitle,
            value: l.profileImportValue,
            onTap: () => context.push('/profile/import'),
          ),
          _ProfileRow(
            id: 'rides',
            icon: Icons.directions_bike,
            title: l.profileRidesTitle,
            value: l.profileRidesValue,
            onTap: () => context.push('/profile/rides'),
          ),
          // #119: eigene Angaben, die älter als 30 Tage sind — nur, wenn
          // es welche gibt; dann sagt der Zähler, wie viele.
          if (stillValid > 0)
            _ProfileRow(
              id: 'still-valid',
              icon: Icons.fact_check_outlined,
              title: l.profileStillValidTitle,
              value: l.profileStillValidValue(stillValid),
              onTap: () => context.push('/profile/still-valid'),
            ),
          // #107: „Sind das dieselben?" — nur, wenn es etwas zu prüfen gibt.
          if (proposals > 0)
            _ProfileRow(
              id: 'merge-proposals',
              icon: Icons.merge_type,
              title: l.profileMergeTitle,
              value: l.profileMergeValue(proposals),
              onTap: () => context.push('/profile/merge-proposals'),
            ),
          _ProfileRow(
            id: 'areas',
            icon: Icons.map_outlined,
            title: l.profileAreasTitle,
            value: switch (areas?.length) {
              null || 0 => l.profileAreasValue,
              final n => l.profileAreasValueCount(n),
            },
            onTap: () => context.push('/profile/areas'),
          ),
          _ProfileRow(
            id: 'notifications',
            icon: Icons.notifications_outlined,
            title: l.profileNotificationsTitle,
            value: push ? l.profileOn : l.profileOff,
            onTap: () => context.push('/profile/notifications'),
          ),
          _ProfileRow(
            id: 'rider',
            icon: Icons.pedal_bike_outlined,
            title: l.profileRiderTitle,
            value: ref.watch(riderProfileProvider).label(l),
            onTap: () => context.push('/profile/rider'),
          ),
          _ProfileRow(
            id: 'appearance',
            icon: Icons.contrast,
            title: l.profileAppearanceTitle,
            value: switch (mode) {
              ThemeMode.light => l.profileAppearanceLight,
              ThemeMode.dark => l.profileAppearanceDark,
              ThemeMode.system => theme.brightness == Brightness.dark
                  ? l.profileAppearanceSystemDark
                  : l.profileAppearanceSystemLight,
            },
            onTap: () => context.push('/profile/appearance'),
          ),
          _ProfileRow(
            id: 'language',
            icon: Icons.translate,
            title: l.profileLanguageTitle,
            value: switch (ref.watch(languageProvider)) {
              AppLanguage.system =>
                l.profileLanguageSystemValue(languageName(Localizations.localeOf(context))),
              final chosen => languageName(chosen.locale!),
            },
            onTap: () => context.push('/profile/language'),
          ),
          _ProfileRow(
            id: 'account',
            icon: Icons.person_outline,
            title: l.profileAccountTitle,
            value: l.profileAccountValue,
            onTap: () => context.push('/profile/account'),
          ),
          // „Entdecken" (#135): alles, was TrailBuddy kann, mit Neu-Punkt.
          _ProfileRow(
            id: 'discover',
            icon: Icons.lightbulb_outline,
            title: l.profileDiscoverTitle,
            value: l.profileDiscoverValue,
            badge: ref.watch(unseenHighlightCountProvider),
            onTap: () => context.push('/profile/discover'),
          ),
          // Über „Über TrailBuddy" (#131): Wer eine Erklärung sucht, landet
          // hier eher als in den Rechtstexten darunter.
          _ProfileRow(
            id: 'help',
            icon: Icons.help_outline,
            title: l.profileHelpTitle,
            value: l.profileHelpValue,
            onTap: () => context.push('/profile/help'),
          ),
          _ProfileRow(
            id: 'about',
            icon: Icons.info_outline,
            title: l.profileAboutTitle,
            value: l.profileAboutValue,
            onTap: () => context.push('/profile/about'),
          ),
          const SizedBox(height: 24),
          Text(
            '${version == null ? '' : 'v$version · '}'
            '${l.profileFooterMapData}',
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
    final l = context.l10n;
    final stats = [
      if (trails != null)
        l.profileStatTrails(
            trails.where((t) => t.pending || t.recordings.any((r) => r.userId == uid)).length),
      if (friendships != null)
        l.profileStatBuddys(friendships.where((f) => f.isAccepted).length),
      if (rides != null) l.profileStatRides(rides.length),
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
    return _ProfilePage(title: context.l10n.profileAccountTitle, children: [
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
      _ProfilePage(title: context.l10n.profileNotificationsTitle, children: const [_PushSection()]);
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _ProfilePage(title: context.l10n.profileAppearanceTitle, children: const [_AppearanceSection()]);
}

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _ProfilePage(title: context.l10n.profileLanguageTitle, children: const [_LanguageSection()]);
}

class RiderProfileScreen extends StatelessWidget {
  const RiderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _ProfilePage(title: context.l10n.profileRiderTitle, children: const [_RiderProfileSection()]);
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _ProfilePage(title: context.l10n.profileAboutTitle, children: const [_AboutSection()]);
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
      title: Text(context.l10n.accountPasswordTitle),
      subtitle: Text(context.l10n.accountPasswordSubtitle),
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
    final l = context.l10n;
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.accountPasswordChanged)),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = changePasswordErrorMessage(l, e));
    } catch (e, stackTrace) {
      logError('Passwort ändern', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.accountPasswordTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _currentController,
              label: l.accountCurrentPassword,
              textInputAction: TextInputAction.next,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _newController,
              label: l.accountPasswordNew(minPasswordLength),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _repeatController,
              label: l.accountPasswordRepeat,
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
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: (!_canSave || _busy) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.commonSave),
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
            .showSnackBar(SnackBar(content: Text(friendlyError(context.l10n, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = Theme.of(context).colorScheme.error;
    final l = context.l10n;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.no_accounts_outlined, color: error),
      title: Text(l.accountDeleteTitle, style: TextStyle(color: error)),
      subtitle: Text(l.accountDeleteSubtitle),
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
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.accountDeleteDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.accountDeleteWhat),
            const SizedBox(height: 12),
            Text(l.accountDeleteBuddys),
            const SizedBox(height: 12),
            Text(
              l.accountDeleteFeedback,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(l.accountDeleteTypeName(widget.username)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.accountUsernameLabel,
                border: const OutlineInputBorder(),
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
          child: Text(l.commonCancel),
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
          child: Text(l.accountDeleteConfirm),
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
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            key: const ValueKey('appearance'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  label: Text(l.profileAppearanceSystem)),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: Text(l.profileAppearanceLight)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: Text(l.profileAppearanceDark)),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(appearanceProvider.notifier).set(s.single),
          ),
        ),
        const SizedBox(height: 4),
        Text(l.profileAppearanceDeviceOnly,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// „Sprache" (#209): wie das Gerät, Deutsch oder Englisch. Gerätelokal
/// wie das Erscheinungsbild; der Dienst liest dieselbe Einstellung.
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<AppLanguage>(
            key: const ValueKey('language'),
            showSelectedIcon: false,
            segments: [
              for (final option in AppLanguage.values)
                ButtonSegment(
                    value: option,
                    label: Text(option.locale == null
                        ? l.profileLanguageSystem
                        : languageName(option.locale!))),
            ],
            selected: {language},
            onSelectionChanged: (s) => ref.read(languageProvider.notifier).set(s.single),
          ),
        ),
        const SizedBox(height: 4),
        Text(l.profileLanguageNote, style: Theme.of(context).textTheme.bodySmall),
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
    final l = context.l10n;
    String learned(double? v) => v == null ? '' : l.riderProfileLearnedMark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RiderProfile>(
            key: const ValueKey('rider-profile'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: RiderProfile.bio,
                  icon: const Icon(Icons.pedal_bike_outlined),
                  label: Text(RiderProfile.bio.label(l))),
              ButtonSegment(
                  value: RiderProfile.ebike,
                  icon: const Icon(Icons.electric_bike_outlined),
                  label: Text(RiderProfile.ebike.label(l))),
            ],
            selected: {profile},
            onSelectionChanged: (s) => ref.read(riderProfileProvider.notifier).set(s.single),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l.riderProfileIntro,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          '${l.riderProfileClimbLine(
            '${params.climbTrackMPerH.round()}', learned(cal.climbTrackMPerH),
            '${params.climbPathMPerH.round()}', learned(cal.climbPathMPerH),
            '${params.pushRateMPerH.round()}', learned(cal.pushRateMPerH),
          )}\n'
          '${l.riderProfileFlatLine('${params.vFlatKmh.round()}', learned(cal.vFlatKmh), '${profile.pathUpFactor}', '${profile.budgetClimbM.round()}')}',
          key: const ValueKey('rider-profile-numbers'),
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          l.riderProfileDeviceOnly,
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(l.riderProfileLearnedTitle, style: text.titleMedium),
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
            label: Text(l.riderProfileLearn),
          ),
          if (!cal.isEmpty)
            TextButton(
              key: const ValueKey('rider-reset'),
              onPressed: () => ref.read(riderCalibrationsProvider.notifier).reset(profile),
              child: Text(l.riderProfileReset(profile.label(l))),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          l.riderProfileLearnExplain,
          style: text.bodySmall,
        ),
      ],
    );
  }

  /// „Bio-Bike: Forstweg 520 hm/h · flach 14 km/h — aus 14 Fahrten (31
  /// Aufstiege), Stand 1.10.2026" oder „Bio-Bike: Vorgaben".
  String _calibLine(RiderProfile p, RiderCalibration c) {
    final l = context.l10n;
    if (c.isEmpty) return l.riderProfileCalibDefaults(p.label(l));
    final values = [
      if (c.climbTrackMPerH != null) l.riderProfileCalibTrack('${c.climbTrackMPerH!.round()}'),
      if (c.climbPathMPerH != null) l.riderProfileCalibPath('${c.climbPathMPerH!.round()}'),
      if (c.pushRateMPerH != null) l.riderProfileCalibPush('${c.pushRateMPerH!.round()}'),
      if (c.vFlatKmh != null) l.riderProfileCalibFlat('${c.vFlatKmh!.round()}'),
    ].join(' · ');
    final rides = l.riderProfileCalibRides(c.rides);
    final climbs = l.riderProfileCalibClimbs(c.sections);
    final at = c.at?.toLocal();
    return at == null
        ? l.riderProfileCalibLine(p.label(l), values, rides, climbs)
        : l.riderProfileCalibLineAsOf(
            p.label(l), values, rides, climbs, DateFormat.yMd(l.localeName).format(at));
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
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(l.profileNotificationsTitle),
          subtitle: Text(l.pushSubtitle),
          value: enabled,
          onChanged: (value) async {
            final problem =
                await ref.read(pushEnabledProvider.notifier).set(l, value);
            if (!context.mounted || problem == null) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(problem)));
          },
        ),
        if (enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.send_outlined),
            title: Text(l.pushTestTitle),
            subtitle: Text(l.pushTestSubtitle),
            onTap: () async {
              final problem =
                  await ref.read(pushEnabledProvider.notifier).sendTest(l);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(problem ?? l.pushTestSent)));
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
    final l = context.l10n;
    final updateStatus = kIsWeb
        ? l.aboutWebAlwaysCurrent
        : !AppDistribution.showsUpdateHints
            // Play-Build: der Store aktualisiert selbst, die App prüft nichts.
            ? l.aboutPlayStore
            : updateInfo != null
                ? l.aboutNewestVersion(updateInfo.latestVersion)
                : l.aboutUpToDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.aboutVersionLine(version, updateStatus),
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
            title: Text(l.aboutPrereleaseTitle),
            subtitle: Text(l.aboutPrereleaseSubtitle),
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
            title: Text(l.aboutPreviewTitle),
            subtitle: Text(l.aboutPreviewSubtitle),
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
            title: Text(l.aboutStableTitle),
            subtitle: Text(l.aboutStableSubtitle),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(AppInfo.webAppUrl),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(l.aboutFeedbackTitle),
          subtitle: Text(l.aboutFeedbackSubtitle),
          onTap: () => showFeedbackFlow(context, ref),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.auto_stories_outlined),
          title: Text(l.aboutChangelogTitle),
          subtitle: Text(l.aboutChangelogSubtitle),
          onTap: () => context.push('/profile/changelog'),
        ),
        // Der Hinweis vom ersten Start, dauerhaft nachlesbar (#131) — als
        // Dialog über `showInfoText`, nicht als eigene Seite: ein Absatz.
        ListTile(
          key: const ValueKey('about-safety-note'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text(l.safetyNoteTitle),
          subtitle: Text(l.aboutSafetySubtitle),
          onTap: () => showInfoText(context, title: l.safetyNoteTitle, text: l.safetyNote),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.code),
          title: Text(l.aboutGithubTitle),
          subtitle: const Text(AppInfo.githubUrl),
          onTap: () => _open(AppInfo.githubUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.public),
          title: Text(l.aboutWebAppTitle),
          subtitle: const Text(AppInfo.webAppUrl),
          onTap: () => _open(AppInfo.webAppUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l.aboutPrivacyTitle),
          subtitle: Text(l.aboutPrivacySubtitle),
          onTap: () => _open(AppInfo.privacyUrlFor(Localizations.localeOf(context))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.info_outline),
          title: Text(l.aboutImpressumTitle),
          subtitle: Text(l.aboutImpressumSubtitle),
          onTap: () => _open(AppInfo.impressumUrlFor(Localizations.localeOf(context))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(l.aboutLicensesTitle),
          subtitle: Text(l.aboutLicensesSubtitle),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'TrailBuddy',
            applicationVersion: version,
            // Das Pseudonym wie in LICENSE: Der Klarname steht nur, wo er
            // Pflicht ist — Impressum und Datenschutzerklärung.
            applicationLegalese: l.aboutLegalese,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.aboutMapData,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l.aboutHeightData(kHeightsAttribution),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
