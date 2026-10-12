import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import 'singletrail_scale.dart';
import 'trail_link.dart';
import 'trail_providers.dart';
import 'trail_takeover.dart';
import 'trail_traits.dart';

/// Der eigene Beitrag zu einem Trail: Name, Schwierigkeit, Charakter,
/// Bewertung, Sichtbarkeit, Beschreibung, Link. Nur für Trails, die man
/// selbst belegt hat — ohne Beleg gibt es keinen Beitrag (Konzept 3). Die
/// Meldung steht seit 0.49.0 NICHT mehr hier („Melden" im Blatt, #101):
/// Melden darf auch, wer keinen Beitrag hat.
///
/// Mit [takeOver] (#102) ist es „Übernehmen": leere Felder vorbelegt mit
/// dem, was das Netz zeigt („Vorschlag aus dem Netz"), Speichern erst mit
/// Sternen — derselbe Weg wie im Zerlege-Blatt, für Trails, deren Beitrag
/// noch am Namen eines Buddys hängt.
Future<void> showTrailDetailsDialog(
    BuildContext context, WidgetRef ref, Trail trail, {bool takeOver = false}) async {
  final current = takeOver
      ? takeOverDetails(trail)
      : trail.myDetails ?? TrailDetails(trailId: trail.id, userId: trail.myId);
  final result = await showDialog<TrailDetails>(
    context: context,
    builder: (_) => _DetailsDialog(initial: current, takeOver: takeOver),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    final outcome = await ref
        .read(trailsProvider.notifier)
        .saveDetails(result);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (outcome) {
      WriteOutcome.done => l.detailsSaved,
      WriteOutcome.doneStale => '${l.detailsSaved}$staleAfterWriteHint',
      WriteOutcome.queued => kQueuedHint,
    })));
  } catch (e, st) {
    logError('Trail-Beitrag speichern', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.initial, this.takeOver = false});
  final TrailDetails initial;
  final bool takeOver;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.initial.name ?? '');
  late final _description =
      TextEditingController(text: widget.initial.description ?? '');
  late final _link =
      TextEditingController(text: switch (widget.initial.link) { final l? => linkForDisplay(l), _ => '' });
  String? _linkError;
  late int? _grade = widget.initial.grade;
  late int? _rating = widget.initial.rating;
  late bool _twoWay = widget.initial.twoWay;
  late final Set<TrailTrait> _traits = {...widget.initial.traits};
  late TrailVisibility _visibility = widget.initial.visibility;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.takeOver ? l.detailsTitleTakeOver : l.detailsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.takeOver)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  key: const ValueKey('details-takeover-intro'),
                  l.detailsTakeOverIntro,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: _name,
              maxLength: kTrailNameMaxLength,
              decoration: InputDecoration(labelText: l.detailsName),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            // Die Skala ist direkt beim Angeben erklärt: die Kurzfassung in
            // jeder Zeile der Auswahl, die ganze Fassung hinter dem „?".
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _grade,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.detailsGrade),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(l.detailsNoGrade)),
                      for (final g in kSingletrailScale)
                        DropdownMenuItem<int?>(
                          value: g.value,
                          child: Text('${g.label} · ${g.short(l)}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _grade = v),
                  ),
                ),
                SingletrailScaleButton(highlight: _grade),
              ],
            ),
            const SizedBox(height: 8),
            // Der Charakter (#72): Mehrfachwahl statt der früheren „Art".
            // Was jedes Merkmal heißt, steht direkt am Chip.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.detailsTraits, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in TrailTrait.values)
                  TrailTraitChip(
                    t,
                    key: ValueKey('trait-${t.db}'),
                    selected: _traits.contains(t),
                    onSelected: (v) => setState(() => v ? _traits.add(t) : _traits.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Die Bewertung (#101): wie gut der Trail gefällt, 1–5 Sterne.
            // Ein zweiter Tipp auf denselben Stern nimmt sie zurück.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.detailsRating, style: Theme.of(context).textTheme.bodySmall),
            ),
            Row(
              children: [
                for (var i = kRatingMin; i <= kRatingMax; i++)
                  IconButton(
                    key: ValueKey('details-rating-$i'),
                    tooltip: l.ratingStarTooltip(i, kRatingMax),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _rating = _rating == i ? null : i),
                    icon: Icon(_rating != null && i <= _rating!
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded),
                  ),
              ],
            ),
            // Richtung (#174): Der Planer fährt den Trail nie gegen seine
            // Richtung — außer hier steht es anders. Vorgabe aus.
            SwitchListTile(
              key: const ValueKey('details-two-way'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.detailsTwoWay),
              subtitle: Text(l.detailsTwoWaySubtitle),
              value: _twoWay,
              onChanged: (v) => setState(() => _twoWay = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TrailVisibility>(
              initialValue: _visibility,
              decoration: InputDecoration(labelText: l.detailsVisibility),
              items: [
                for (final v in TrailVisibility.values)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => setState(() => _visibility = v ?? _visibility),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              decoration: InputDecoration(labelText: l.detailsDescription),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            // Link zur Quelle (#103): etwa die Seite des Vereins. Nur https,
            // Query und Fragment fallen weg (sanitizeLink).
            TextField(
              key: const ValueKey('details-link'),
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.detailsLink,
                hintText: l.detailsLinkHint,
                errorText: _linkError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('details-save'),
          // Übernehmen heißt bewerten (Rework E2).
          onPressed: widget.takeOver && _rating == null ? null : () {
            final linkText = _link.text.trim();
            final link = sanitizeLink(linkText);
            if (linkText.isNotEmpty && link == null) {
              setState(() => _linkError = l.detailsLinkError);
              return;
            }
            // Jedes Feld mit: Wer hier eines vergisst, löscht es beim
            // Speichern still (Lehre aus #113).
            Navigator.of(context).pop(TrailDetails(
              trailId: widget.initial.trailId,
              userId: widget.initial.userId,
              username: widget.initial.username,
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              grade: _grade,
              traits: {..._traits},
              rating: _rating,
              twoWay: _twoWay,
              link: link,
              visibility: _visibility,
            ));
          },
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
