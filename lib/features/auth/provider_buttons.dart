import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../data/auth_repository.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';

/// Die Anbieter, die das Projekt freigibt (#398). Ein Fehler (kein Netz,
/// fremde Antwort) heißt: keine Knöpfe, nur die E-Mail — kein Fund fürs
/// Protokoll, der Login-Screen steht oft ohne Empfang da.
final enabledSignInProvidersProvider =
    FutureProvider.autoDispose<Set<SignInProvider>>((ref) async {
  try {
    return await ref.read(authRepositoryProvider).enabledProviders();
  } catch (_) {
    return const {};
  }
});

/// Was ein gescheiterter Rücksprung vom Anbieter sagt (#398) — die
/// Gründe aus GoTrues `error_description`, die bei der Einrichtung
/// 2026-10-29 vorkamen. Unbekanntes geht ins Protokoll, damit der nächste
/// Grund einen eigenen Satz bekommen kann.
String providerReturnErrorMessage(AppLocalizations l, AuthException error) {
  final text = error.message.toLowerCase();
  if (text.contains('multiple accounts')) return l.authReturnMultipleAccounts;
  if (text.contains('expired')) return l.authReturnExpired;
  if (error.code == 'access_denied') return l.authReturnCancelled;
  logError('Rücksprung vom Anbieter', error, StackTrace.current);
  return l.authReturnFailed;
}

/// Markenname, Zeichen und ob es einfarbig ist (dann in der Textfarbe,
/// damit GitHub im Dunkeln nicht verschwindet).
extension SignInProviderLook on SignInProvider {
  String get label => switch (this) {
        SignInProvider.google => 'Google',
        SignInProvider.microsoft => 'Microsoft',
        SignInProvider.facebook => 'Facebook',
        SignInProvider.github => 'GitHub',
        SignInProvider.discord => 'Discord',
        SignInProvider.linkedin => 'LinkedIn',
      };

  String get asset => 'assets/auth/$name.svg';

  bool get monochrome => this == SignInProvider.github;
}

/// „oder weiter mit" und je freigegebenem Anbieter ein Knopf mit seinem
/// Zeichen — als Reihe, nicht als Liste: Sechs Knöpfe untereinander
/// schöben das Formular aus dem Bild. Der Name steht im Tooltip und in
/// der Semantik. Nichts freigegeben ⇒ nichts zu sehen.
class ProviderSignInButtons extends ConsumerStatefulWidget {
  const ProviderSignInButtons({super.key, this.enabled = true});

  /// Aus, solange das Formular darüber arbeitet.
  final bool enabled;

  @override
  ConsumerState<ProviderSignInButtons> createState() =>
      _ProviderSignInButtonsState();
}

class _ProviderSignInButtonsState extends ConsumerState<ProviderSignInButtons> {
  bool _busy = false;

  Future<void> _signIn(SignInProvider provider) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // Kehrt zurück, sobald der Browser offen ist; die Sitzung kommt
      // später über den Rücksprung, der Router folgt ihr.
      await ref.read(authRepositoryProvider).signInWithProvider(provider);
    } catch (e, stackTrace) {
      if (!looksOffline(e)) logError('Anmelden über ${provider.label}', e, stackTrace);
      messenger.showSnackBar(
          SnackBar(content: Text(l.authProviderFailed(provider.label))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers =
        ref.watch(enabledSignInProvidersProvider).valueOrNull ?? const {};
    if (providers.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(l.authProviderDivider,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in SignInProvider.values)
              if (providers.contains(p))
                Tooltip(
                  message: l.authProviderButton(p.label),
                  child: OutlinedButton(
                    key: ValueKey('signin-${p.name}'),
                    onPressed: enabled ? () => _signIn(p) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(56, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Semantics(
                      label: l.authProviderButton(p.label),
                      child: SvgPicture.asset(
                        p.asset,
                        width: 22,
                        height: 22,
                        colorFilter: p.monochrome
                            ? ColorFilter.mode(scheme.onSurface, BlendMode.srcIn)
                            : null,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
