import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/auth/pending_code.dart';

import '../fakes/fake_settings.dart';

// #399: Der Merker für einen Code aus der Mail — wie lange er gilt und
// dass er nur seine eigene Ansicht öffnet.
void main() {
  final at = DateTime.utc(2026, 10, 27, 12);

  test('Rundlauf', () {
    final raw = PendingCode(PendingCodeKind.reset, 'a@example.org', at).encode();
    final back = PendingCode.decode(raw, now: at.add(const Duration(minutes: 59)))!;
    expect(back.kind, PendingCodeKind.reset);
    expect(back.email, 'a@example.org');
    expect(back.requestedAt, at);
  });

  test('nach einer Stunde ist der Code abgelaufen, der Merker auch', () {
    final raw = PendingCode(PendingCodeKind.reset, 'a@example.org', at).encode();
    expect(PendingCode.decode(raw, now: at.add(const Duration(minutes: 61))), isNull);
  });

  test('Unlesbares ist kein Fehler, nur kein Merker', () {
    expect(PendingCode.decode('{kaputt', now: at), isNull);
    expect(PendingCode.decode('{"kind":"x","email":"a","at":"y"}', now: at), isNull);
  });

  test('ein Reset-Merker öffnet nicht die Registrierung', () {
    final settings = FakeSettings(
        pendingAuthCode: PendingCode(PendingCodeKind.reset, 'a@example.org', at).encode());
    final soon = at.add(const Duration(minutes: 1));
    expect(PendingCode.read(settings, PendingCodeKind.signup, now: soon), isNull);
    expect(PendingCode.read(settings, PendingCodeKind.reset, now: soon)?.email, 'a@example.org');
  });

  test('Vergessen nimmt nur die eigene Art mit', () async {
    final raw = PendingCode(PendingCodeKind.signup, 'a@example.org', DateTime.now()).encode();
    final settings = FakeSettings(pendingAuthCode: raw);
    PendingCode.forget(settings, PendingCodeKind.reset);
    await Future<void>.delayed(Duration.zero);
    expect(settings.pendingAuthCode, raw);
    PendingCode.forget(settings, PendingCodeKind.signup);
    await Future<void>.delayed(Duration.zero);
    expect(settings.pendingAuthCode, isNull);
  });
}
