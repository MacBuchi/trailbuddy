import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/l10n.dart';
import '../map/host_requests.dart';

/// Wie oft die Seite die Zählung neu liest.
const kDevHostRefresh = Duration(seconds: 1);

/// „Entwicklung" (#596 H7): nur in der Dev-App und der Web-Vorschau
/// (`devToolsVisibleProvider`). Zeigt, wie oft die App seit dem Start
/// oder dem letzten „Zurücksetzen" beim Kartenhost war, je Art — die
/// Grundlinie für `docs/konzept-traffic.md`.
class DevScreen extends ConsumerStatefulWidget {
  const DevScreen({super.key});

  @override
  ConsumerState<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends ConsumerState<DevScreen> {
  HostRequestSnapshot? _snapshot;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(kDevHostRefresh, (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final snapshot = await ref.read(hostRequestsProvider).read();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  Future<void> _reset() async {
    await ref.read(hostRequestsProvider).reset();
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final snapshot = _snapshot;
    final counts = snapshot?.counts ?? const {};
    final total = counts.values.fold(0, (a, b) => a + b);
    final numbers = AppFonts.numbers(theme.textTheme.titleMedium);

    Widget row(String label, int value, {Key? key, bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: strong
                      ? theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyLarge,
                ),
              ),
              Text('$value', key: key, style: numbers),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.profileDevTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.devHostTitle, style: theme.textTheme.titleLarge),
          if (snapshot != null)
            Text(
              l.devHostSince(DateFormat.Hms().format(snapshot.since)),
              key: const ValueKey('dev-host-since'),
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          const SizedBox(height: 12),
          for (final kind in HostRequestKind.values)
            row(
              hostRequestKindLabel(l, kind),
              counts[kind] ?? 0,
              key: ValueKey('dev-host-${kind.name}'),
            ),
          Divider(color: palette.line),
          row(
            l.devHostTotal,
            total,
            key: const ValueKey('dev-host-total'),
            strong: true,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('dev-host-reset'),
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              label: Text(l.devHostReset),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.devHostNote,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

String hostRequestKindLabel(AppLocalizations l, HostRequestKind kind) =>
    switch (kind) {
      HostRequestKind.map => l.devHostKindMap,
      HostRequestKind.ways => l.devHostKindWays,
      HostRequestKind.heights => l.devHostKindHeights,
      HostRequestKind.manifest => l.devHostKindManifest,
      HostRequestKind.pois => l.devHostKindPois,
      HostRequestKind.names => l.devHostKindNames,
      HostRequestKind.other => l.devHostKindOther,
    };
