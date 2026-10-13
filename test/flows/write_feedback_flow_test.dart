// Sofortige Rückmeldung und Start ohne Netz (#183, Feldbericht zu 0.73.0:
// „das Setzen vom Schwierigkeitslevel dauert teils Sekunden … dann sollte
// wenigstens verblasst der Status direkt gesetzt werden").
//
// Was ein Tipp setzt, steht SOFORT da — verblasst und mit „wird
// übertragen", bis Schreiben und Neuladen durch sind. Ohne Netz übernimmt
// der Ausgangskorb nahtlos; ein Serverfehler nimmt den Wert sichtbar
// zurück. Und der Kaltstart zeigt die Kopie, wenn das Netz zögert, statt
// auf die Wiederholungen von postgrest zu warten.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trail_cache.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    trails.seedTrail(annaId, name: 'Roots');
  });

  final grade4 = find.byKey(const ValueKey('own-grade-4'));
  Finder gradeCaption(String text) =>
      find.descendant(of: find.byKey(const ValueKey('own-grade-pending')), matching: find.text(text));
  bool selected(WidgetTester tester, Finder chip) => tester.widget<ChoiceChip>(chip).selected;
  double opacityOf(WidgetTester tester, Finder chip) => tester
      .widget<Opacity>(find.ancestor(of: chip, matching: find.byType(Opacity)).first)
      .opacity;

  Future<void> openRoots(WidgetTester tester, {FakeOutbox? outbox}) async {
    await pumpApp(tester, backend, trails: trails, outbox: outbox);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Roots'));
    await settle(tester);
    await tester.ensureVisible(grade4);
  }

  testWidgets('der S-Grad steht sofort da, verblasst, bis er auf dem Server liegt',
      (tester) async {
    await openRoots(tester);
    final net = Completer<void>();
    trails.saveDetailsGate = net.future;
    await tester.tap(grade4);
    await tester.pump();
    expect(selected(tester, grade4), isTrue, reason: 'vor der ersten Antwort des Netzes');
    expect(opacityOf(tester, grade4), lessThan(1));
    expect(gradeCaption('wird übertragen …'), findsOneWidget);
    expect(find.text('Dein Beitrag wird übertragen …'), findsOneWidget);
    expect(findLabel('S4 · 1 Einschätzung'), findsOneWidget, reason: 'Schild und Karte zählen ihn schon');
    // Auch nach Sekunden ohne Antwort bleibt er stehen.
    await settle(tester, frames: 30);
    expect(selected(tester, grade4), isTrue);

    net.complete();
    await settle(tester, frames: 12);
    expect(trails.details.single.grade, 4);
    expect(selected(tester, grade4), isTrue);
    expect(opacityOf(tester, grade4), 1);
    expect(find.text('wird übertragen …'), findsNothing);
    expect(find.byKey(const ValueKey('pending-details')), findsNothing);
  });

  testWidgets('nach dem Speichern wird nur der Beitrag nachgelesen, nicht das Netz', (tester) async {
    // Feldbericht 2026-10-02: Ein Stern lud jede Linie neu — über die
    // Leitung, und die Karte übertrug danach jede Linie neu an MapLibre.
    trails.seedTrail(annaId, name: 'Wald', lat: 48.2);
    await openRoots(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
    final before = container.read(trailsProvider).value!;
    final wald = before.firstWhere((t) => t.displayName(l10nDe) == 'Wald');
    final fetches = trails.recordingFetches;

    await tester.tap(grade4);
    await settle(tester, frames: 12);
    expect(trails.details.firstWhere((d) => d.name == 'Roots').grade, 4);
    expect(trails.recordingFetches, fetches, reason: 'die Linien hat der Beitrag nicht geändert');
    final after = container.read(trailsProvider).value!;
    expect(after.firstWhere((t) => t.displayName(l10nDe) == 'Roots').grade, 4);
    expect(after.firstWhere((t) => t.displayName(l10nDe) == 'Wald'), same(wald),
        reason: 'ein unveränderter Trail bleibt dasselbe Objekt — samt geglätteter Linie');
    expect(after.firstWhere((t) => t.displayName(l10nDe) == 'Roots').points,
        same(before.firstWhere((t) => t.displayName(l10nDe) == 'Roots').points));
  });

  testWidgets('ohne Netz: der Wert bleibt stehen und sagt, dass er wartet', (tester) async {
    final outbox = FakeOutbox();
    await openRoots(tester, outbox: outbox);
    final net = Completer<void>();
    trails.saveDetailsGate = net.future;
    await tester.tap(grade4);
    await tester.pump();
    expect(gradeCaption('wird übertragen …'), findsOneWidget);
    net.completeError(const SocketException('offline'));
    await settle(tester, frames: 12);
    expect((outbox.jobs.single as DetailsJob).details.grade, 4);
    expect(selected(tester, grade4), isTrue);
    expect(opacityOf(tester, grade4), lessThan(1));
    expect(gradeCaption('nur auf dem Gerät — wartet auf Übertragung'), findsOneWidget);
    expect(find.text('wird übertragen …'), findsNothing);
  });

  testWidgets('ein Serverfehler nimmt den Wert sichtbar zurück', (tester) async {
    await openRoots(tester);
    final net = Completer<void>();
    trails.saveDetailsGate = net.future;
    await tester.tap(grade4);
    await tester.pump();
    expect(selected(tester, grade4), isTrue);
    net.completeError(StateError('42501: RLS'));
    await settle(tester, frames: 12);
    expect(selected(tester, grade4), isFalse);
    expect(find.text('wird übertragen …'), findsNothing);
    expect(trails.details.single.grade, isNull);
  });

  testWidgets('eine Meldung steht sofort im Verlauf, mit „wird übertragen"', (tester) async {
    await openRoots(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('report-condition-4')));
    await settle(tester);
    final net = Completer<void>();
    trails.reportGate = net.future;
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 4);
    expect(find.textContaining('wird übertragen'), findsWidgets);
    net.complete();
    await settle(tester, frames: 12);
    expect(trails.reports.single.condition, 4);
    expect(find.textContaining('wird übertragen'), findsNothing);
  });

  testWidgets('Kaltstart, das Netz zögert: die Kopie nach kurzer Frist, dann der frische Stand',
      (tester) async {
    final cache = FakeTrailCache();
    await pumpApp(tester, backend, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    expect(cache.snapshot, isNotNull);

    // Neustart: ein Balken, über den nichts kommt. Erst den Baum
    // abbauen — ein zweites `pumpApp` behielte den ProviderScope, und das
    // wäre kein Kaltstart.
    await tester.pumpWidget(const SizedBox());
    final backend2 = FakeBackend();
    final anna = backend2.addUser(username: 'anna');
    backend2.signInAs(anna.id);
    cache.uid = anna.id;
    trails = FakeTrailRepository(myId: () => backend2.currentUserId ?? '');
    trails.seedTrail(anna.id, name: 'Roots');
    trails.seedTrail(anna.id, name: 'Neu seit gestern', lat: 48.2);
    final net = Completer<void>();
    trails.fetchGate = net.future;
    await pumpApp(tester, backend2, trails: trails, trailCache: cache);
    // 2 s — die Frist ist 1,5 s; ohne sie stünde die Karte bis zum
    // Aufgeben des Netzes leer.
    await settle(tester, frames: 20);
    final notice = find.byKey(const ValueKey('cached-notice'));
    expect(notice, findsOneWidget);
    expect(find.textContaining('das Netz antwortet noch'), findsOneWidget);
    expect(find.textContaining('Kein Empfang'), findsNothing, reason: 'Netz ist da, nur langsam');

    net.complete();
    await settle(tester, frames: 12);
    expect(notice, findsNothing);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 12);
    expect(find.text('Neu seit gestern'), findsOneWidget);
  });
}
