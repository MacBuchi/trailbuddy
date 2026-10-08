// Der Ausgangskorb im Test (#30): im Speicher statt als Datei, mit den
// Schaltern, die die Regeln prüfbar machen.
import 'package:trailbuddy/data/outbox.dart';

class FakeOutbox implements Outbox {
  final jobs = <OutboxJob>[];
  String? uid;

  /// Lässt [append] scheitern — der Fall „der Korb selbst kann nicht
  /// schreiben": Dann muss der ursprüngliche Netzfehler durchkommen.
  bool failOnAppend = false;

  /// Was `isDurable` sagt — `false` steht für den Browser, der den
  /// Speicher nicht zusichert (#153).
  bool durable = true;

  int appends = 0;
  int replaces = 0;

  @override
  Future<List<OutboxJob>> read({required String uid}) async =>
      this.uid == null || this.uid == uid ? List.of(jobs) : const [];

  @override
  Future<void> append(OutboxJob job, {required String uid}) async {
    if (failOnAppend) throw Exception('kein Platz (Fake)');
    appends++;
    this.uid = uid;
    jobs.add(job);
  }

  @override
  Future<void> replaceAll(List<OutboxJob> next, {required String uid}) async {
    replaces++;
    this.uid = uid;
    jobs
      ..clear()
      ..addAll(next);
  }

  @override
  Future<bool> isDurable() async => durable;
}
