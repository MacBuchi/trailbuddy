// Konto-Dialoge des Profils, die nicht Passwort oder Löschen sind.
//
// Eigene Datei mit Absicht: profile_screen.dart soll die Liste bleiben,
// die Konto-Verwaltung wächst für sich. Muster ist `_ChangePasswordDialog`
// von dort — Kachel öffnet Dialog, Fehler als FormNotice im Dialog, Erfolg
// als SnackBar nach dem Schließen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../core/errors.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/password_field.dart';
import '../../core/widgets/resend_button.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/profile.dart';
import 'profile_providers.dart';

/// Kachel „Benutzername ändern" — nur sinnvoll, wenn das Profil geladen
/// ist, sonst gäbe es keinen aktuellen Namen zum Vorbefüllen.
class ChangeUsernameTile extends ConsumerWidget {
  const ChangeUsernameTile({super.key, required this.username});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = username;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.badge_outlined),
      title: Text(context.l10n.accountUsernameTitle),
      // Der aktuelle Name, wie die E-Mail-Kachel die Adresse zeigt — seit
      // 0.41.0 steht die Kachel auf der Seite „Konto", nicht mehr unter
      // dem Profilkopf.
      subtitle: Text(name ?? context.l10n.accountUsernameEmpty),
      trailing: const Icon(Icons.chevron_right),
      enabled: name != null,
      onTap: name == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => _ChangeUsernameDialog(current: name),
              ),
    );
  }
}

/// Kachel „E-Mail-Adresse ändern" — die Adresse ist die Konto-Identität:
/// Die Freundessuche matcht auf sie, und der Reset-Code geht an ihr
/// Postfach. Wer den Zugriff auf das alte Postfach verliert, ist ein
/// vergessenes Passwort vom ausgesperrten Konto entfernt.
class ChangeEmailTile extends ConsumerWidget {
  const ChangeEmailTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auf die Sitzungs-Events hören: Der vollzogene Wechsel bringt eine
    // frische Sitzung mit (verifyOTP), und die Kachel muss die neue
    // Adresse SOFORT zeigen. Ohne diese Zeile stand am Emulator die
    // alte Adresse da, bis irgendetwas anderes neu baute —
    // Read-after-write gilt auch hier.
    ref.watch(authStateProvider);
    final email = ref.watch(authRepositoryProvider).currentEmail;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.alternate_email),
      title: Text(context.l10n.accountEmailTitle),
      subtitle: Text(email ?? context.l10n.accountEmailEmpty),
      trailing: const Icon(Icons.chevron_right),
      enabled: email != null,
      onTap: email == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => _ChangeEmailDialog(current: email),
              ),
    );
  }
}

/// Zwei Phasen wie der Registrieren-Screen: erst aktuelles Passwort und
/// neue Adresse, dann die Codes aus BEIDEN Postfächern („Secure email
/// change" — ein gestohlenes Session-Token allein kann das Konto nicht
/// umziehen). Erst der zweite Code vollzieht den Wechsel; gemessen gegen
/// echtes GoTrue.
class _ChangeEmailDialog extends ConsumerStatefulWidget {
  const _ChangeEmailDialog({required this.current});

  final String current;

  @override
  ConsumerState<_ChangeEmailDialog> createState() =>
      _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends ConsumerState<_ChangeEmailDialog> {
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _oldCodeController = TextEditingController();
  final _newCodeController = TextEditingController();
  bool _codesPhase = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _emailController.dispose();
    _oldCodeController.dispose();
    _newCodeController.dispose();
    super.dispose();
  }

  String get _newEmail => _emailController.text.trim();

  bool get _canRequest =>
      _passwordController.text.isNotEmpty &&
      _newEmail.contains('@') &&
      _newEmail.toLowerCase() != widget.current.toLowerCase();

  bool get _canConfirm =>
      _oldCodeController.text.trim().length == 6 &&
      _newCodeController.text.trim().length == 6;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changeEmail(
            currentPassword: _passwordController.text,
            newEmail: _newEmail,
          );
      if (mounted) setState(() => _codesPhase = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = emailChangeErrorMessage(e));
    } catch (e, stackTrace) {
      logError('E-Mail ändern', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = context.l10n;
    try {
      final auth = ref.read(authRepositoryProvider);
      // Feste Reihenfolge: erst der Code der ALTEN Adresse (wird nur
      // quittiert), dann der der NEUEN — der vollzieht den Wechsel und
      // bringt die frische Sitzung mit.
      await auth.confirmEmailChange(
          email: widget.current, code: _oldCodeController.text.trim());
      await auth.confirmEmailChange(
          email: _newEmail, code: _newCodeController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.accountEmailChanged)),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = emailChangeErrorMessage(e));
    } catch (e, stackTrace) {
      logError('E-Mail ändern bestätigen', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).hintColor);
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.accountEmailTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _codesPhase
              ? [
                  FormNotice(
                    message: l.accountEmailCodesSent,
                    tone: NoticeTone.info,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _oldCodeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: l.accountEmailOldCode),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newCodeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: l.accountEmailNewCode),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ResendButton(
                    label: l.accountEmailResend,
                    onResend: _request,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    FormNotice(message: _error!, tone: NoticeTone.error),
                  ],
                ]
              : [
                  Text(l.accountEmailCurrent(widget.current), style: hint),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _passwordController,
                    label: l.accountCurrentPassword,
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        labelText: l.accountEmailNew),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // Die Suche matcht auf die exakte Adresse — das
                    // gehört gesagt, BEVOR jemand wechselt.
                    l.accountEmailSearchHint,
                    style: hint,
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
          onPressed: _busy ||
                  (_codesPhase ? !_canConfirm : !_canRequest)
              ? null
              : (_codesPhase ? _confirm : _request),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_codesPhase ? l.accountConfirm : l.accountNext),
        ),
      ],
    );
  }
}

/// Kachel „Andere Geräte abmelden" — der Handgriff nach einem
/// Passwortwechsel auf verlorenem oder geteiltem Gerät: Das alte
/// Passwort gilt dort nicht mehr, die laufende Sitzung aber schon.
class SignOutOtherDevicesTile extends StatelessWidget {
  const SignOutOtherDevicesTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.phonelink_erase_outlined),
      title: Text(context.l10n.accountSignOutOthersTitle),
      subtitle: Text(context.l10n.accountSignOutOthersSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _SignOutOtherDevicesDialog(),
      ),
    );
  }
}

/// Mit Rückfrage: Ein Fehltipp würde sonst still das Tablet zu Hause
/// abmelden, und dort sieht es aus wie ein Fehler der App.
class _SignOutOtherDevicesDialog extends ConsumerStatefulWidget {
  const _SignOutOtherDevicesDialog();

  @override
  ConsumerState<_SignOutOtherDevicesDialog> createState() =>
      _SignOutOtherDevicesDialogState();
}

class _SignOutOtherDevicesDialogState
    extends ConsumerState<_SignOutOtherDevicesDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = context.l10n;
    try {
      await ref.read(authRepositoryProvider).signOutOtherDevices();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.accountSignOutOthersDone)),
      );
    } catch (e, stackTrace) {
      logError('Andere Geräte abmelden', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.accountSignOutOthersTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.accountSignOutOthersBody),
          if (_error != null) ...[
            const SizedBox(height: 16),
            FormNotice(message: _error!, tone: NoticeTone.error),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.profileSignOut),
        ),
      ],
    );
  }
}

class _ChangeUsernameDialog extends ConsumerStatefulWidget {
  const _ChangeUsernameDialog({required this.current});

  final String current;

  @override
  ConsumerState<_ChangeUsernameDialog> createState() =>
      _ChangeUsernameDialogState();
}

class _ChangeUsernameDialogState extends ConsumerState<_ChangeUsernameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  /// Was am eingetippten Namen nicht stimmt — dieselbe Prüfung wie bei
  /// der Registrierung.
  ///
  /// Solange nichts eingetippt wurde, meldet sie nichts: Ein Dialog, der
  /// sich beim Öffnen selbst beschwert, liest sich wie ein Fehler.
  String? get _problem =>
      _trimmed.isEmpty ? null : usernameProblem(_trimmed);

  bool get _canSave =>
      _problem == null && _trimmed.isNotEmpty && _trimmed != widget.current;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = context.l10n;
    try {
      await ref
          .read(myProfileProvider.notifier)
          .updateUsername(_trimmed);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.accountUsernameChanged)),
      );
    } catch (e, stackTrace) {
      // Der vergebene Name ist der erwartbare Fall und KEIN Fall für
      // error_reports — nur Unerwartetes wird gemeldet.
      if (usernameChangeErrorMessage(e) == friendlyError(e)) {
        logError('Benutzername ändern', e, stackTrace);
      }
      if (mounted) setState(() => _error = usernameChangeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.accountUsernameTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.accountUsernameNew,
                helperText: l.accountUsernameMin(minUsernameLength),
                // Der Grund steht am Feld, nicht nur im grauen Knopf:
                // Ein „Speichern", das ohne Erklärung tot ist, sieht wie
                // ein Fehler der App aus.
                errorText: _problem,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => (_canSave && !_busy) ? _save() : null,
            ),
            const SizedBox(height: 8),
            Text(
              // Die Suche läuft über das Namens-Präfix — das gehört
              // gesagt, bevor jemand seinen bekannten Namen aufgibt.
              l.accountUsernameSearchHint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
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
