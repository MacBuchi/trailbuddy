import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/motion.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/profile.dart';
import '../profile/profile_providers.dart';

/// Die Namenswahl nach der ersten Anmeldung über einen Anbieter (#422):
/// Ein Konto über Google & Co. heißt vom Trigger `trailbuddy_<8 Zeichen>`,
/// und bevor die Karte kommt, fragt die App einmal nach einem eigenen
/// Namen. „Später" ist erlaubt (Betreiber 2026-10-29) — der Name bleibt,
/// das Konto ändert ihn jederzeit.
///
/// Um die GANZE Hülle, nicht nur ihren Body: Solange der Schritt steht,
/// gibt es keine Reiterleiste und keine Karte — und damit weder
/// Sicherheitshinweis noch Tour (`MapScreen._firstStart`), die kommen
/// erst danach, wie bei einem Konto über E-Mail.
///
/// Ob der Schritt steht, sagt der Name auf dem Server, nicht das Gerät:
/// Lädt der Browser die Seite mitten im Schritt neu, steht er wieder da,
/// bis ein Name gespeichert ist. Gemerkt wird nur, dass er für dieses
/// Konto erledigt ist (`Settings.usernameStepDoneFor`) — sonst wartete
/// jeder Start auf das Profil.
class UsernameGate extends ConsumerStatefulWidget {
  const UsernameGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UsernameGate> createState() => _UsernameGateState();
}

class _UsernameGateState extends ConsumerState<UsernameGate> {
  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider);
    final settings = ref.read(settingsProvider);
    if (uid == null ||
        settings.usernameStepDoneFor.contains(uid) ||
        ref.read(authRepositoryProvider).externalProvider == null) {
      return widget.child;
    }
    final profile = ref.watch(myProfileProvider);
    // Nur der erste Start nach der Anmeldung wartet hier — danach steht
    // der Merker. Ohne Netz geht es zur Karte, gefragt wird beim nächsten
    // Start.
    if (profile.isLoading && !profile.hasValue) {
      return const Scaffold(body: CenteredTrailLoader());
    }
    final username = profile.valueOrNull?.username;
    if (username == null) return widget.child;
    if (!isAssignedUsername(username)) {
      settings
          .addUsernameStepDone(uid)
          .catchError((Object e, StackTrace s) => logError('Namenswahl merken', e, s));
      return widget.child;
    }
    return UsernameStep(onLater: () async {
      await settings.addUsernameStepDone(uid);
      if (mounted) setState(() {});
    });
  }
}

/// Die Seite selbst: ein Feld, „Weiter" und „Später".
class UsernameStep extends ConsumerStatefulWidget {
  const UsernameStep({super.key, required this.onLater});

  final Future<void> Function() onLater;

  @override
  ConsumerState<UsernameStep> createState() => _UsernameStepState();
}

class _UsernameStepState extends ConsumerState<UsernameStep> {
  late final _controller = TextEditingController(text: _suggestion());
  String? _error;
  bool _busy = false;

  /// Der Nutzername beim Anbieter, wenn er als Benutzername taugt — nie
  /// der Klarname (`handleFromProviderMetadata`). Ob er frei ist, sagt
  /// erst das Speichern: Eine Vorab-Frage wäre ein Verzeichnis-Orakel
  /// mehr und beim Tippen auf „Weiter" schon wieder alt.
  String _suggestion() {
    final handle = ref.read(authRepositoryProvider).providerHandle;
    if (handle == null || usernameProblem(context.l10n, handle) != null) {
      return '';
    }
    return handle;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  /// Wie „Benutzername ändern": still, solange nichts dasteht.
  String? get _problem =>
      _trimmed.isEmpty ? null : usernameProblem(context.l10n, _trimmed);

  bool get _canSave => _problem == null && _trimmed.isNotEmpty && !_busy;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = context.l10n;
    try {
      // Das neu geladene Profil trägt den Namen — die Hülle sieht ihn und
      // gibt die Karte frei.
      await ref.read(myProfileProvider.notifier).updateUsername(_trimmed);
    } catch (e, stackTrace) {
      // Vergeben ist erwartbar und kein Fall für error_reports.
      if (usernameChangeErrorMessage(l, e) == friendlyError(l, e)) {
        logError('Benutzername wählen', e, stackTrace);
      }
      if (mounted) setState(() => _error = usernameChangeErrorMessage(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _later() async {
    setState(() => _busy = true);
    await widget.onLater();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.usernameStepTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(l.usernameStepBody,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('username-step-field'),
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.signupUsernameLabel,
                    helperText: l.accountUsernameMin(minUsernameLength),
                    errorText: _problem,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _canSave ? _save() : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  FormNotice(message: _error!, tone: NoticeTone.error),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.usernameStepSave),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _later,
                  child: Text(l.usernameStepLater),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
