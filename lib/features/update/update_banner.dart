import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update_check.dart';
import '../../core/widgets/form_notice.dart';
import '../../data/apk_installer.dart';
import '../../l10n/l10n.dart';
import 'update_installer.dart';

/// Update-Banner für diese Sitzung ausgeblendet? Das X schaltet nur für
/// die Sitzung stumm (PilzBuddy #425): Der nächste Start ist der Rückweg.
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Der Hinweis auf eine neue Version, oben auf der Karte. Nur im
/// GitHub-Vertrieb — im Play-Build ist `updateInfoProvider` still.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateInfoProvider).valueOrNull;
    final dismissed = ref.watch(updateBannerDismissedProvider);
    if (info == null || dismissed) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.system_update_alt),
            title: Text(context.l10n.updateBannerTitle(info.latestVersion)),
            onTap: () => showUpdateDialog(context, info),
            trailing: IconButton(
              tooltip: context.l10n.updateBannerHide,
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(updateBannerDismissedProvider.notifier).state = true,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) =>
    showDialog<void>(context: context, builder: (_) => _UpdateDialog(info: info));

/// Release-Notes, Fortschritt und Übergabe an den System-Installer. Der
/// Browser-Weg bleibt als Rückfalltür: der einzige ohne Zusatzberechtigung
/// und ohne Method-Channel, und dorthin führt jeder Fehlschlag.
class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  double? _progress;
  bool _busy = false;
  UpdateFailure? _failure;

  Future<void> _openInBrowser() => launchUrl(
        Uri.parse(widget.info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _failure = null;
      _progress = null;
    });
    final failure = await ref.read(updateInstallerProvider).downloadAndInstall(
          widget.info,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
        );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  String _failureText(AppLocalizations l, UpdateFailure failure) => switch (failure) {
        UpdateFailure.notAllowed => l.updateFailNotAllowed,
        UpdateFailure.downloadFailed => l.updateFailDownload,
        UpdateFailure.installFailed => l.updateFailInstall,
      };

  @override
  Widget build(BuildContext context) {
    final notes = widget.info.releaseNotes?.trim();
    final installer = ref.watch(updateInstallerProvider);
    final failure = _failure;
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.updateDialogTitle(widget.info.latestVersion)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(installer.supported ? l.updateDialogInstall : l.updateDialogBrowser),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text(
                _progress == null
                    ? l.updateLoading
                    : l.updateLoadingPercent((_progress! * 100).round()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (failure != null) ...[
              const SizedBox(height: 12),
              FormNotice(message: _failureText(l, failure), tone: NoticeTone.error),
              if (failure == UpdateFailure.notAllowed) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => ref.read(apkInstallerProvider).openSettings(),
                  icon: const Icon(Icons.settings, size: 18),
                  label: Text(l.updateOpenSettings),
                ),
              ],
            ],
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.updateWhatsNew, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(notes, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.updateLater),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _openInBrowser,
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: Text(l.updateInBrowser),
        ),
        if (installer.supported)
          FilledButton.icon(
            onPressed: _busy ? null : _install,
            icon: const Icon(Icons.download, size: 18),
            label: Text(l.updateInstall),
          ),
      ],
    );
  }
}
