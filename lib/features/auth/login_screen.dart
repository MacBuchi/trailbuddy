import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/password_field.dart';
import '../../core/widgets/resend_button.dart';
import '../../core/widgets/trailbuddy_logo.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import 'pending_code.dart';
import 'provider_buttons.dart';

/// Drei Zustände statt zwei: „Passwort vergessen" ist ein eigener Modus, der
/// nur die E-Mail abfragt — ein sichtbares Passwortfeld daneben verleitet
/// dazu, dort das (vergessene) Passwort einzutippen. Nach dem Anfordern
/// folgt [_Mode.code], wo Code aus der Mail und neues Passwort zusammen
/// eingegeben werden.
enum _Mode { signIn, forgot, code }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _repeatController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  String? _notice;
  NoticeTone _noticeTone = NoticeTone.info;
  bool _busy = false;

  /// Ein Code aus der Zeit vor dem Neuladen (#399), bis sein Hinweis
  /// gesetzt ist — der braucht die Sprache, und die gibt es erst nach
  /// `initState`.
  String? _restoredEmail;

  /// Gelesen in `initState`, weil `dispose` den Merker räumt und `ref`
  /// dort nicht mehr gilt.
  late final Settings _settings;

  /// Scheitert der Rücksprung vom Anbieter (#398), landet man hier — ohne
  /// diesen Hinweis stumm, als wäre nichts geschehen.
  StreamSubscription<AuthException>? _providerErrors;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(settingsProvider);
    _providerErrors =
        ref.read(authRepositoryProvider).providerReturnErrors.listen((error) {
      if (!mounted) return;
      setState(() {
        _notice = providerReturnErrorMessage(context.l10n, error);
        _noticeTone = NoticeTone.error;
      });
    });
    final pending = PendingCode.read(_settings, PendingCodeKind.reset);
    if (pending != null) {
      _mode = _Mode.code;
      _emailController.text = pending.email;
      _restoredEmail = pending.email;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final email = _restoredEmail;
    if (email == null) return;
    _restoredEmail = null;
    _notice = context.l10n.loginCodeSent(email);
    _noticeTone = NoticeTone.success;
  }

  @override
  void dispose() {
    // Wer den Screen verlässt (angemeldet, zur Registrierung), wartet auf
    // keinen Code mehr. Ein Neuladen des Browsers kommt hier nie vorbei —
    // genau dafür bleibt der Merker stehen.
    PendingCode.forget(_settings, PendingCodeKind.reset);
    _providerErrors?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  void _switchTo(_Mode mode) => setState(() {
        // Zurück zur Anmeldung heißt: auf diesen Code wartet niemand mehr.
        if (mode == _Mode.signIn) PendingCode.forget(_settings, PendingCodeKind.reset);
        _mode = mode;
        _notice = null;
        _codeController.clear();
        _newPasswordController.clear();
        _repeatController.clear();
      });

  /// Hinweis samt Tonfall setzen. Erfolg und Fehlschlag sahen in der
  /// Urfassung gleich aus — ein blankes `Text` unter dem Formular.
  void _setNotice(String message, NoticeTone tone) => setState(() {
        _notice = message;
        _noticeTone = tone;
      });

  /// Sieht das nach einer Adresse aus?
  ///
  /// Dieselbe Prüfung für Anfordern UND Erneut-Senden. In PilzBuddy fehlte
  /// sie im zweiten Weg: Bei leerem Feld ging die Anfrage trotzdem raus,
  /// GoTrue antwortete „Password recovery requires an email" (400), und
  /// die App meldete unbeirrt „ein neuer Code ist unterwegs" — eine Mail,
  /// die es nie gab. Das Feld steht auch im Code-Modus da und lässt sich
  /// leeren.
  bool _looksLikeEmail(String email) => email.isNotEmpty && email.contains('@');

  /// Fordert den Code an. Erfolg und Fehlschlag melden dasselbe: Ein
  /// Unterschied würde verraten, ob es zu der Adresse ein Konto gibt.
  Future<void> _sendResetCode() async {
    final l = context.l10n;
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _setNotice(l.loginInvalidEmail, NoticeTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetCode(email);
    } catch (e, stackTrace) {
      // Nur protokollieren, nicht zeigen — siehe oben. Ein abgelehnter
      // Mailversand ist dabei kein Fund fürs Protokoll, sondern das
      // Limit bei der Arbeit (siehe looksLikeMailRateLimit).
      //
      // **Und ein 504 auch nicht.** Ein `logError` mit eigenem Kontext
      // meldet ALLES — `worthReporting` fasst es nicht an, weil der
      // Aufrufer sich bewusst fürs Melden entschieden hat. Hier wäre das
      // zu breit: In PilzBuddy waren in einer Woche 11 von 13 Berichten
      // `AuthRetryableFetchException(statusCode: 504)` aus genau dieser
      // Zeile, also das, was `looksOffline` überall sonst als fehlenden
      // Empfang führt. Ein normaler Vorgang, der den Digest anführt,
      // verstopft ihn für echte Funde.
      if (!looksLikeMailRateLimit(e) && !looksOffline(e)) {
        logError('Passwort-Reset anfordern', e, stackTrace);
      }
    } finally {
      if (mounted) {
        PendingCode.remember(_settings, PendingCodeKind.reset, email);
        setState(() {
          _busy = false;
          _mode = _Mode.code;
          _notice = l.loginCodeSent(email);
          _noticeTone = NoticeTone.success;
        });
      }
    }
  }

  /// Schickt den Code noch einmal — für den häufigsten Fall, dass die Mail
  /// im Spam liegt oder gelöscht wurde. Ohne das bliebe nur, den Reset ganz
  /// von vorn zu beginnen.
  ///
  /// Meldet wie [_sendResetCode] in jedem Fall dasselbe: Ein Unterschied
  /// zwischen Erfolg und Fehlschlag würde hier verraten, ob es zu der
  /// Adresse ein Konto gibt — auch ein Rate-Limit-Hinweis täte das, denn er
  /// käme nur, wenn wirklich eine Mail rausging.
  Future<void> _resendResetCode() async {
    final l = context.l10n;
    final email = _emailController.text.trim();
    // Die eine Ausnahme von „immer dasselbe melden": Ohne Adresse gibt es
    // nichts zu verraten, und „unterwegs" wäre schlicht falsch.
    if (!_looksLikeEmail(email)) {
      _setNotice(l.loginInvalidEmail, NoticeTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetCode(email);
    } catch (e, stackTrace) {
      // Dieselbe Grenze wie beim ersten Versand: Rate-Limit und
      // fehlender Empfang sind keine Funde.
      if (!looksLikeMailRateLimit(e) && !looksOffline(e)) {
        logError('Reset-Code erneut anfordern', e, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _setNotice(l.loginCodeResent(email), NoticeTone.success);
      }
    }
  }

  Future<void> _resetPassword() async {
    final l = context.l10n;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _setNotice(l.authCodeMissing, NoticeTone.error);
      return;
    }
    if (_newPasswordController.text.length < minPasswordLength) {
      _setNotice(l.loginNewPasswordTooShort(minPasswordLength), NoticeTone.error);
      return;
    }
    if (_newPasswordController.text != _repeatController.text) {
      _setNotice(l.loginPasswordsDiffer, NoticeTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPasswordWithCode(
            email: _emailController.text.trim(),
            code: code,
            newPassword: _newPasswordController.text,
          );
      // Kein Erfolgs-Hinweis nötig: Das geänderte Passwort meldet die
      // Sitzung an, der Router führt zur Karte.
    } on AuthException catch (e) {
      // Die Recovery-Sitzung darf nicht liegen bleiben, wenn das Ändern
      // scheiterte — sonst steckt jemand halb angemeldet fest.
      await _discardRecoverySession();
      if (mounted) _setNotice(resetErrorMessage(l, e), NoticeTone.error);
    } catch (e, stackTrace) {
      logError('Passwort zurücksetzen', e, stackTrace);
      await _discardRecoverySession();
      if (mounted) _setNotice(friendlyError(l, e), NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardRecoverySession() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth.currentSession == null) return;
    try {
      await auth.signOut();
    } catch (e, stackTrace) {
      // Aufräumen darf den Fehlerfall nicht überdecken.
      logError('Recovery-Sitzung verwerfen', e, stackTrace);
    }
  }

  Future<void> _signIn() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // Erst nach erfolgreicher Anmeldung darf der Passwortmanager speichern.
      TextInput.finishAutofillContext();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loginErrorMessage(l, e))));
      }
    } catch (e, stackTrace) {
      logError('Login', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _primaryLabel(AppLocalizations l) => switch (_mode) {
        _Mode.signIn => l.loginSignIn,
        _Mode.forgot => l.loginRequestCode,
        _Mode.code => l.loginSaveNewPassword,
      };

  VoidCallback get _primaryAction => switch (_mode) {
        _Mode.signIn => _signIn,
        _Mode.forgot => _sendResetCode,
        _Mode.code => _resetPassword,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
                // Logo, Wortmarke und ein Satz, linksbündig (Design 1g).
                const Align(
                  alignment: Alignment.centerLeft,
                  child: TrailBuddyMark(size: 64),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: TrailBuddyWordmark(),
                ),
                const SizedBox(height: 8),
                Text(l.loginTagline,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 40),
                // Ohne AutofillGroup registrieren sich die Felder nicht beim
                // Autofill-Dienst — Passwortmanager sehen das Formular sonst
                // gar nicht. Abbruch beim Verlassen, gespeichert wird erst
                // nach erfolgreicher Anmeldung (finishAutofillContext).
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: l.authEmailLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_mode == _Mode.signIn) ...[
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _passwordController,
                          label: l.authPasswordLabel,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _busy ? null : _signIn(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_mode == _Mode.code) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l.authCodeLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _newPasswordController,
                    label: l.loginNewPasswordLabel(minPasswordLength),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _repeatController,
                    label: l.loginRepeatPasswordLabel,
                    onSubmitted: (_) => _busy ? null : _resetPassword(),
                    onChanged: (_) => setState(() {}),
                  ),
                  PasswordMatchHint(
                    password: _newPasswordController.text,
                    repeated: _repeatController.text,
                  ),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 16),
                  FormNotice(message: _notice!, tone: _noticeTone),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _primaryAction,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_primaryLabel(l)),
                ),
                if (_mode == _Mode.signIn) ...[
                  TextButton(
                    onPressed: () => _switchTo(_Mode.forgot),
                    child: Text(l.loginForgot),
                  ),
                  TextButton(
                    onPressed: () => context.go('/signup'),
                    child: Text(l.loginToSignup),
                  ),
                  // Google, GitHub & Co. (#398) — nur, was das Projekt
                  // freigibt; ohne Freigabe sieht der Screen aus wie zuvor.
                  ProviderSignInButtons(enabled: !_busy),
                ] else ...[
                  if (_mode == _Mode.code)
                    ResendButton(
                      onResend: _resendResetCode,
                      enabled: !_busy,
                      label: l.loginResendCode,
                    ),
                  TextButton(
                    onPressed: () => _switchTo(_Mode.signIn),
                    child: Text(l.loginBack),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
