// Die eine Zeile nach einer Fahrt (#516 Schritt 6, Konzept-Routing 12.5a):
// „1 100 hm geschafft — Limit fürs Bio-Bike von 800 auf 1 100 hm
// anheben?" (oder dasselbe für die Distanz, oder beide in einem Satz) mit
// „Anheben" und „Nein", oder — sah die Fahrt nach E-Bike aus — „War es
// eins?". Kein Dialog, keine Benachrichtigung: Sie steht im
// Zerlege-Blatt am Ende der Aufzeichnung und, blieb sie unbeantwortet,
// einmal im Einstieg des Planers.
//
// Jede Antwort gilt sofort (wie die Bestätigung im Zerlege-Blatt, nicht
// erst mit „Behalten") und leert die gemerkte Frage; danach sagt die
// Zeile, was gilt, mit „Rückgängig".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../routing/loop_planner.dart' show LoopPrefs;
import '../routing/loop_planner_controller.dart';
import '../routing/ride_calibrator.dart' show calibratedRiderProvider;
import '../routing/route_profile.dart';
import 'climb_limit_offer.dart';
import 'ride_providers.dart';
import 'ride_track.dart';

/// Der Vorschlag nach einer eben beendeten Aufzeichnung, mit den Profilen,
/// mit denen geplant wird, und gemerkt für den Einstieg des Planers (bis
/// eine Antwort ihn leert). Ein Fehler kostet nur die Frage.
ClimbLimitOffer? offerClimbLimitAfter(WidgetRef ref, Ride ride) {
  try {
    final offer = climbLimitOfferFor(
      ride,
      ref.read(loopPlannerProvider).prefs,
      bio: ref.read(calibratedRiderProvider(RiderProfile.bio)),
      ebike: ref.read(calibratedRiderProvider(RiderProfile.ebike)),
    );
    if (offer != null) {
      ref
          .read(settingsProvider)
          .setClimbLimitPending(offer.encode())
          .catchError(
            (Object e, StackTrace s) => logError('Limit-Frage merken', e, s),
          );
    }
    return offer;
  } catch (e, s) {
    logError('Limit-Frage nach der Fahrt', e, s);
    return null;
  }
}

/// Die gemerkte Frage für den Einstieg des Planers — EINMAL: Sie wird beim
/// Lesen geleert (12.5a: „danach ist sie weg"). Null, wenn keine da ist
/// oder das Limit inzwischen ohnehin darüber steht.
ClimbLimitOffer? takePendingClimbLimit(WidgetRef ref) {
  final settings = ref.read(settingsProvider);
  final offer = ClimbLimitOffer.parse(settings.climbLimitPending);
  if (settings.climbLimitPending == null) return null;
  settings
      .setClimbLimitPending(null)
      .catchError(
        (Object e, StackTrace s) => logError('Limit-Frage vergessen', e, s),
      );
  if (offer == null) return null;
  final prefs = ref.read(loopPlannerProvider).prefs;
  return limitOfferStands(prefs, offer) ? offer : null;
}

class ClimbLimitRow extends ConsumerStatefulWidget {
  const ClimbLimitRow({super.key, required this.offer});

  final ClimbLimitOffer offer;

  @override
  ConsumerState<ClimbLimitRow> createState() => _ClimbLimitRowState();
}

class _ClimbLimitRowState extends ConsumerState<ClimbLimitRow> {
  ClimbLimitAnswer? _answer;

  /// Die Limits des Rads, als die Frage stand — „von 800" bleibt stehen,
  /// auch wenn die Antwort es ändert.
  late final LoopPrefs _from = ref.read(loopPlannerProvider).prefs;

  ClimbLimitOffer get _offer => widget.offer;

  LoopPlannerNotifier get _planner => ref.read(loopPlannerProvider.notifier);

  Future<void> _setRideBike(RiderProfile p) async {
    try {
      await ref.read(ridesProvider.notifier).setProfile([_offer.rideId], p);
    } catch (e, s) {
      logError('Limit-Frage: Rad der Fahrt', e, s);
    }
  }

  void _apply(
    ClimbLimitAnswer Function(LoopPrefs prefs, ClimbLimitOffer offer) answerOf,
  ) {
    late ClimbLimitAnswer answer;
    _planner.updateLimits((prefs) => (answer = answerOf(prefs, _offer)).after);
    ref
        .read(settingsProvider)
        .setClimbLimitPending(null)
        .catchError(
          (Object e, StackTrace s) => logError('Limit-Frage vergessen', e, s),
        );
    setState(() => _answer = answer);
    if (answer.movedToEbike) _setRideBike(RiderProfile.ebike);
  }

  void _undo() {
    final answer = _answer!;
    _planner.updateLimits((prefs) => prefs.withLimitsOf(answer.before));
    if (answer.movedToEbike) _setRideBike(_offer.bike);
    setState(() => _answer = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final answer = _answer;
    final bike = _offer.bike.label(l);
    final climb = _offer.climbM.round(), km = _offer.distKm.round();
    final fromM = _from.climbOf(_offer.bike).round();
    final fromKm = _from.distOf(_offer.bike).round();
    if (answer != null) {
      String raised(RiderProfile p) {
        final b = p.label(l);
        final m = answer.after.climbOf(p), d = answer.after.distOf(p);
        final upM = m != answer.before.climbOf(p);
        final upKm = d != answer.before.distOf(p);
        return upM && upKm
            ? l.bothLimitRaised(b, m.round(), d.round())
            : upKm
            ? l.distLimitRaised(b, d.round())
            : l.climbLimitRaised(b, m.round());
      }

      final text = answer.movedToEbike
          ? (answer.raisedBike == null
                ? l.climbLimitMoved
                : '${l.climbLimitMoved} · ${raised(answer.raisedBike!)}')
          : answer.raisedBike != null
          ? raised(answer.raisedBike!)
          : _offer.toM != null && _offer.toKm != null
          ? l.bothLimitDeclined(bike, fromM, fromKm)
          : _offer.toKm != null
          ? l.distLimitDeclined(bike, fromKm)
          : l.climbLimitDeclined(bike, fromM);
      return Row(
        key: const ValueKey('climb-limit'),
        children: [
          Expanded(
            child: Text(
              text,
              key: const ValueKey('climb-limit-done'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppPalette.of(context).muted,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('climb-limit-undo'),
            onPressed: _undo,
            child: Text(l.commonUndo),
          ),
        ],
      );
    }
    final (question, yes, no) = _offer.askEbike
        ? (
            l.climbLimitEbikeAsk(climb),
            (
              key: 'climb-limit-ebike-yes',
              text: l.climbLimitEbikeYes,
              answer: ebikeClimbLimit,
            ),
            (
              key: 'climb-limit-ebike-no',
              text: l.climbLimitEbikeNo,
              answer: raiseClimbLimit,
            ),
          )
        : (
            switch ((_offer.toM, _offer.toKm)) {
              (final m?, final d?) => l.bothLimitAsk(
                climb,
                km,
                bike,
                m.round(),
                d.round(),
              ),
              (null, final d?) => l.distLimitAsk(km, bike, fromKm, d.round()),
              (final m, _) => l.climbLimitAsk(
                climb,
                bike,
                fromM,
                (m ?? _offer.climbM).round(),
              ),
            },
            (
              key: 'climb-limit-raise',
              text: l.climbLimitRaise,
              answer: raiseClimbLimit,
            ),
            (
              key: 'climb-limit-keep',
              text: l.climbLimitKeep,
              answer: declineClimbLimit,
            ),
          );
    return Column(
      key: const ValueKey('climb-limit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                Icons.trending_up,
                size: 20,
                color: AppPalette.of(context).accentText,
              ),
            ),
            Expanded(
              child: Text(
                question,
                key: const ValueKey('climb-limit-text'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              key: ValueKey(yes.key),
              onPressed: () => _apply(yes.answer),
              child: Text(yes.text),
            ),
            TextButton(
              key: ValueKey(no.key),
              onPressed: () => _apply(no.answer),
              child: Text(no.text),
            ),
          ],
        ),
      ],
    );
  }
}
