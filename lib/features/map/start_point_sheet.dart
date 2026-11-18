// Blatt und Dialog der gemerkten Startpunkte (#543,
// `docs/konzept-startpunkte.md` 4 und 5.2).
//
// [rememberStartPoint] ist der EINE Weg zum Anlegen — Ort-Blatt, langer
// Druck, später Planer-Ergebnis und „Mein Standort merken" enden alle im
// selben kleinen Dialog: Name, „Buddys sehen ihn", Merken.
// [showStartPointSheet] ist das Blatt am Pin: Name, von wem, Start, Ziel,
// Navi-App; am eigenen Punkt Umbenennen, Sichtbarkeit und Löschen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/start_point.dart';
import '../../models/trail.dart' show TrailVisibility;
import '../friends/buddy_alias.dart' show buddyNamesViewProvider;
import '../trails/trail_navigation.dart' show navigateToPoint;
import '../trails/trail_providers.dart';
import 'start_point_layer.dart';

/// Fragt Name und Sichtbarkeit ab und merkt den Punkt bei [at] — oder
/// nichts, wenn der Dialog abgebrochen wird. [name] belegt das Feld vor
/// (der Name des Ortes), [shared] den Schalter (Vorgabe „Buddys",
/// Konzept 4). [home] ist „Mein Standort merken" und der eigene Standort
/// als Start: Dort steht unter dem Schalter die Warnung vor der Haustür
/// (Konzept 4, A10 — ein Satz, kein Riegel). Das Ergebnis sagt eine
/// Leiste; die Obergrenze (9.2) ist ein Satz, kein Fehler.
Future<void> rememberStartPoint(
  BuildContext context,
  WidgetRef ref,
  LatLng at, {
  String? name,
  bool shared = true,
  bool home = false,
}) async {
  final result = await showDialog<({String name, bool shared})>(
    context: context,
    builder: (_) =>
        StartPointDialog(name: name ?? '', shared: shared, home: home),
  );
  if (result == null || !context.mounted) return;
  final myId = ref.read(currentUserIdProvider);
  if (myId == null) return;
  await _save(
    context,
    ref,
    StartPoint(
      clientId: newClientId(),
      userId: myId,
      name: result.name,
      lat: at.latitude,
      lon: at.longitude,
      visibility: result.shared
          ? TrailVisibility.buddies
          : TrailVisibility.private,
      createdAt: DateTime.now(),
    ),
    done: context.l10n.startPointSaved,
  );
}

Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  StartPoint point, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    final outcome = await ref
        .read(trailsProvider.notifier)
        .saveStartPoint(point);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            WriteOutcome.done => done,
            WriteOutcome.doneStale => l.staleAfterWrite(done),
            WriteOutcome.queued => l.queuedHint,
          }),
        ),
      );
  } catch (e, st) {
    // Die Obergrenze ist kein Fehler, sondern ein Satz (Konzept 9.2).
    if (e is! StartPointLimitException) logError('Startpunkt speichern', e, st);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
  }
}

/// Der Dialog: Name (1–60 Zeichen) und „Buddys sehen ihn". Gibt beides
/// zurück, oder `null` bei „Abbrechen". [title] ist „Als Startpunkt
/// merken" oder, beim Umbenennen, „Umbenennen" — dann ohne Schalter.
class StartPointDialog extends StatefulWidget {
  const StartPointDialog({
    super.key,
    required this.name,
    required this.shared,
    this.rename = false,
    this.home = false,
  });

  final String name;
  final bool shared;
  final bool rename;

  /// Der Punkt ist der eigene Standort — die Warnung vor der Haustür.
  final bool home;

  @override
  State<StartPointDialog> createState() => _StartPointDialogState();
}

class _StartPointDialogState extends State<StartPointDialog> {
  late final _name = TextEditingController(text: widget.name);
  late bool _shared = widget.shared;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = clampStartPointName(_name.text);
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, shared: _shared));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.rename ? l.startPointRename : l.startPointRemember),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('start-point-name'),
            controller: _name,
            autofocus: true,
            maxLength: kStartPointNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.startPointName,
              hintText: l.startPointNameHint,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (!widget.rename)
            SwitchListTile(
              key: const ValueKey('start-point-shared'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.startPointShared),
              subtitle: Text(
                _shared ? l.startPointSharedOn : l.startPointSharedOff,
              ),
              value: _shared,
              onChanged: (v) => setState(() => _shared = v),
            ),
          if (widget.home && !widget.rename)
            Text(
              l.startPointHomeWarning,
              key: const ValueKey('start-point-home-warning'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.of(context).warningText,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('start-point-save'),
          onPressed: clampStartPointName(_name.text).isEmpty ? null : _submit,
          child: Text(
            widget.rename ? l.commonSave : l.startPointRememberAction,
          ),
        ),
      ],
    );
  }
}

/// Das Blatt am Pin. [onStart] und [onTarget] geben den Punkt an den
/// Planer (wie am Ort, `takePlace`), [onRemember] merkt einen fremden
/// Punkt als eigenen. Das Blatt schließt vorher — die Rückrufe laufen
/// deshalb im Kontext der KARTE, nicht in dem des Blatts (der ist danach
/// weg, und ein Dialog daraus käme nie zurück; im Test gefunden).
/// Navi-App, Umschalten, Umbenennen und Löschen bleiben im Blatt bzw.
/// nehmen sich Leiste und Notifier, bevor es schließt.
Future<void> showStartPointSheet(
  BuildContext context,
  StartPoint point, {
  required VoidCallback onStart,
  required VoidCallback onTarget,
  required void Function(StartPoint point) onRemember,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => _StartPointSheet(
    pointKey: point.key,
    fallback: point,
    onStart: onStart,
    onTarget: onTarget,
    onRemember: onRemember,
  ),
);

class _StartPointSheet extends ConsumerWidget {
  const _StartPointSheet({
    required this.pointKey,
    required this.fallback,
    required this.onStart,
    required this.onTarget,
    required this.onRemember,
  });

  final String pointKey;
  final StartPoint fallback;
  final VoidCallback onStart;
  final VoidCallback onTarget;
  final void Function(StartPoint point) onRemember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final palette = AppPalette.of(context);
    final myId = ref.watch(currentUserIdProvider);
    // Der aktuelle Stand: Umschalten und Umbenennen zeigen sich sofort.
    // Ist der Punkt weg (gelöscht, Freundschaft beendet), bleibt der
    // letzte bekannte stehen, bis das Blatt zugeht.
    final point =
        ref
            .watch(startPointsProvider)
            .where((p) => p.key == pointKey)
            .firstOrNull ??
        fallback;
    final own = myId != null && point.isMine(myId);
    final names = ref.watch(buddyNamesViewProvider);
    final String who;
    if (!own) {
      who = l.startPointFrom(names.of(point.userId, point.username));
    } else if (point.pending) {
      who = point.sending ? l.sheetValueSending : l.startPointQueued;
    } else {
      who = point.shared ? l.startPointSharedOn : l.startPointSharedOff;
    }
    void pop() => Navigator.of(context).pop();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StartPointPin(own: own, pending: point.pending),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point.name,
                    key: const ValueKey('start-point-title'),
                    style: text.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              who,
              key: const ValueKey('start-point-who'),
              style: text.bodyMedium?.copyWith(
                color: own ? null : palette.buddyText,
              ),
            ),
            const SizedBox(height: 12),
            // Dieselben Wörter wie am Ort (#516): „Als Ziel" rechnet
            // sofort, „Als Start" öffnet den Planer.
            FilledButton.icon(
              key: const ValueKey('start-point-as-start'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                pop();
                onStart();
              },
              icon: const Icon(Icons.trip_origin),
              label: Text(l.sheetAsStart),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('start-point-as-target'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                pop();
                onTarget();
              },
              icon: const Icon(Icons.sports_score),
              label: Text(l.sheetAsTarget),
            ),
            const SizedBox(height: 8),
            // Die Anfahrt mit dem Auto ist der häufigste Fall (Konzept 5.2).
            OutlinedButton.icon(
              key: const ValueKey('start-point-navigate'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                // Erst die Navi-App fragen (sie holt sich die Leiste
                // synchron), dann schließen.
                unawaited(
                  navigateToPoint(context, point.position, name: point.name),
                );
                pop();
              },
              icon: const Icon(Icons.directions_outlined),
              label: Text(l.mapMenuExternalNav),
            ),
            if (own) ...[
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('start-point-shared-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.startPointShared),
                subtitle: Text(
                  point.shared ? l.startPointSharedOn : l.startPointSharedOff,
                ),
                value: point.shared,
                onChanged: (v) => unawaited(
                  _save(
                    context,
                    ref,
                    point.copyWith(
                      visibility: v
                          ? TrailVisibility.buddies
                          : TrailVisibility.private,
                    ),
                    done: v ? l.startPointNowShared : l.startPointNowPrivate,
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('start-point-rename'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.startPointRename),
                onTap: () async {
                  final result = await showDialog<({String name, bool shared})>(
                    context: context,
                    builder: (_) => StartPointDialog(
                      name: point.name,
                      shared: point.shared,
                      rename: true,
                    ),
                  );
                  if (result == null ||
                      result.name == point.name ||
                      !context.mounted) {
                    return;
                  }
                  await _save(
                    context,
                    ref,
                    point.copyWith(name: result.name),
                    done: l.startPointRenamed,
                  );
                },
              ),
              ListTile(
                key: const ValueKey('start-point-delete'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(l.commonDelete),
                onTap: () => unawaited(_delete(context, ref, point)),
              ),
            ] else ...[
              // Ein fremder Punkt wird nicht weitergereicht (A2) — wer ihn
              // behalten will, merkt ihn selbst neu (Konzept 8).
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('start-point-remember-copy'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  pop();
                  onRemember(point);
                },
                icon: const Icon(Icons.flag_outlined),
                label: Text(l.startPointRemember),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Löschen schließt das Blatt; „Rückgängig" merkt denselben Punkt
  /// wieder (dieselbe `client_id`, ein Upsert).
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StartPoint point,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final notifier = ref.read(trailsProvider.notifier);
    Navigator.of(context).pop();
    try {
      await notifier.deleteStartPoint(point.clientId);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('start-point-deleted'),
            content: Text(l.startPointDeleted(point.name)),
            action: SnackBarAction(
              label: l.commonUndo,
              onPressed: () => unawaited(
                notifier
                    .saveStartPoint(
                      point.copyWith(pending: false, sending: false),
                    )
                    .catchError((Object e, StackTrace st) {
                      logError('Startpunkt wiederherstellen', e, st);
                      return WriteOutcome.done;
                    }),
              ),
            ),
            persist: false,
          ),
        );
    } catch (e, st) {
      logError('Startpunkt löschen', e, st);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }
}
