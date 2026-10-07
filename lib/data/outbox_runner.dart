// Die Wiedervorlage des Ausgangskorbs (#30): Aufträge der Reihe nach
// senden, das Ergebnis in EINEM Schreibvorgang festhalten.
//
// Frei von Riverpod, damit jede Regel ohne Backend prüfbar ist. Wer den
// Namen (und S-Grad) nach dem Beisteuern übernimmt ([adoptDetails]),
// entscheidet der
// Aufrufer: Er kennt den Bestand und überschreibt keinen Namen, den
// jemand bewusst eingetragen hat.
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/errors.dart';
import '../models/trail.dart' show TrailTrait;
import 'feedback_repository.dart';
import 'outbox.dart';
import 'trail_repository.dart';

typedef OutboxRunResult = ({int sent, int remaining, int failed});

class OutboxRunner {
  OutboxRunner({
    required this.repository,
    required this.feedback,
    required this.outbox,
    required this.adoptDetails,
  });

  final TrailRepository repository;

  /// Für [FeedbackJob] (#218).
  final FeedbackRepository feedback;
  final Outbox outbox;

  /// Nach dem Beisteuern: den Namen (und den Link, #103) aus der Datei als
  /// eigenen übernehmen, wenn noch keiner steht — und den S-Grad aus dem
  /// Zerlege-Blatt.
  final Future<void> Function(String trailId, String name, int? grade,
      Set<TrailTrait> traits, String? link, int? rating) adoptDetails;

  /// Nach so vielen erfolglosen Anläufen gilt ein Auftrag als abgelehnt.
  /// Netzfehler und das Tageslimit zählen NICHT — die brechen den Lauf ab,
  /// ohne den Zähler anzufassen.
  static const maxAttempts = 5;

  var _running = false;

  Future<OutboxRunResult> run({required String uid}) async {
    if (_running) return (sent: 0, remaining: 0, failed: 0);
    _running = true;
    try {
      return await _run(uid: uid);
    } finally {
      _running = false;
    }
  }

  Future<OutboxRunResult> _run({required String uid}) async {
    final jobs = await outbox.read(uid: uid);
    if (jobs.isEmpty) return (sent: 0, remaining: 0, failed: 0);

    final remaining = <OutboxJob>[];
    var sent = 0;
    var stopped = false;

    for (final job in jobs) {
      if (stopped || job.failure != null) {
        remaining.add(job); // Wartet auf den nächsten Anlauf bzw. eine Entscheidung.
        continue;
      }
      try {
        switch (job) {
          case ContributeJob():
            final trailId = await repository.contribute(
              coords: job.coords,
              eles: job.eles,
              source: job.source,
              recordedAt: job.recordedAt,
              clientId: job.id,
            );
            final name = job.name?.trim() ?? '';
            if (name.isNotEmpty ||
                job.grade != null ||
                job.traits.isNotEmpty ||
                job.link != null ||
                job.rating != null) {
              await adoptDetails(trailId, name, job.grade, job.traits, job.link, job.rating);
            }
          case DetailsJob():
            await repository.saveDetails(job.details);
            if (job.legacyStatus case final status?) {
              await repository.report(
                trailId: job.details.trailId,
                status: status,
                onSite: false,
                reportedAt: job.legacyStatusAt ?? job.createdAt,
                clientId: job.id,
              );
            }
            final note = job.note?.trim() ?? '';
            if (note.isNotEmpty) {
              await repository.addNote(trailId: job.details.trailId, body: note);
            }
          case ReportJob():
            await repository.report(
              trailId: job.trailId,
              status: job.status,
              condition: job.condition,
              onSite: job.onSite,
              reportedAt: job.createdAt,
              clientId: job.id,
            );
            final note = job.note?.trim() ?? '';
            if (note.isNotEmpty) {
              await repository.addNote(trailId: job.trailId, body: note);
            }
          case FeedbackJob():
            await feedback.submit(job.type, job.message,
                appVersion: job.appVersion, clientId: job.id);
        }
        sent++;
      } catch (error) {
        // Kein Netz, keine Sitzung, Tageslimit: Der Lauf endet hier, ohne
        // etwas als gescheitert zu markieren. Der nächste Anlauf macht
        // in derselben Reihenfolge weiter.
        if (looksOffline(error) ||
            error is NotSignedInException ||
            error is DailyLimitException) {
          remaining.add(job);
          stopped = true;
          continue;
        }
        final attempts = job.attempts + 1;
        // Eine Ablehnung des Servers (RLS, Constraint, zu kurze Linie)
        // wird durch Wiederholen nicht besser.
        final done = _isFinal(error) || attempts >= maxAttempts;
        remaining.add(job.copyWith(
          attempts: attempts,
          failure: done ? friendlyError(error) : null,
        ));
      }
    }

    await outbox.replaceAll(remaining, uid: uid);
    return (
      sent: sent,
      remaining: remaining.length,
      failed: remaining.where((j) => j.failure != null).length,
    );
  }

  /// Ein `23505` kommt hier nicht an: `contribute_recording` beantwortet
  /// eine bekannte `client_id` mit der Kennung von damals.
  bool _isFinal(Object error) =>
      error is WriteRejectedException || error is PostgrestException;
}
