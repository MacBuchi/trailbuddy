// Eine gescannte Einladung (#502): Der QR trägt für alle dieselbe Adresse —
// die Installationsseite mit dem Namen. Wer die App hat, fängt Android sie ab
// (Intent-Filter im Manifest); hier wird geprüft, wie die App sie erkennt.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/friends/invite_link.dart';

void main() {
  test('der Link aus dem QR nennt den Namen', () {
    expect(inviteNameFromLink(Uri.parse(
        'https://macbuchi.github.io/trailbuddy/install.html?invite=Jan')), 'Jan');
    expect(inviteNameFromLink(Uri.parse(
        'https://macbuchi.github.io/trailbuddy/?invite=M%C3%BCller%20%26%20Co')), 'Müller & Co',
        reason: 'Umlaute und Sonderzeichen im QR müssen wieder ankommen');
    expect(inviteNameFromLink(Uri.parse(
        'https://macbuchi.github.io/trailbuddy/?invite=  Jan  ')), 'Jan');
  });

  test('alles andere öffnet die Buddys nicht', () {
    // Ohne Namen keine Einladung, und fremde Seiten nicht: denselben
    // Intent-Filter hat Android für jeden Link unter macbuchi.github.io.
    expect(inviteNameFromLink(Uri.parse('https://macbuchi.github.io/trailbuddy/install.html')), null);
    expect(inviteNameFromLink(Uri.parse('https://macbuchi.github.io/trailbuddy/?invite=')), null);
    expect(inviteNameFromLink(Uri.parse('https://macbuchi.github.io/trailbuddy/?invite=%20')), null);
    expect(inviteNameFromLink(Uri.parse('https://example.com/trailbuddy/?invite=Jan')), null);
    expect(inviteNameFromLink(Uri.parse('http://macbuchi.github.io/trailbuddy/?invite=Jan')), null);
  });

  test('die Einladung bleibt, bis die Buddys sie holen', () {
    launchLink = Uri.parse('https://macbuchi.github.io/trailbuddy/install.html?invite=Jan');
    addTearDown(() => launchLink = null);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(inviteProvider), 'Jan');
    expect(container.read(inviteProvider.notifier).take(), 'Jan');
    // Einmal geholt: sonst füllte jeder spätere Besuch dieselbe Suche.
    expect(container.read(inviteProvider), null);
  });
}
