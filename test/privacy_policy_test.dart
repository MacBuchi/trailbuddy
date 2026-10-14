/// Wacht über die Rechtsseiten und über die Regel „kein Netzziel ohne
/// Eintrag in der Datenschutzerklärung" (PilzBuddy #110). Nicht die
/// Erklärung wird auf Vollständigkeit geprüft, sondern der umgekehrte Weg:
/// Taucht in `lib/` oder `web/` ein Host auf, den hier niemand eingeordnet
/// hat, bricht der Test.
library;

import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_info.dart';

const _privacy = 'web/datenschutz.html';
const _impressum = 'web/impressum.html';
const _deleteAccount = 'web/konto-loeschen.html';

/// Die englischen Höflichkeitsübersetzungen (#209) — je deutsche Seite
/// genau eine, verbindlich bleibt die deutsche.
const _english = {
  _privacy: 'web/privacy.html',
  _impressum: 'web/imprint.html',
  _deleteAccount: 'web/delete-account.html',
};

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path fehlt');
  return file.readAsStringSync();
}

void main() {
  test('die verlinkten Seiten liegen wirklich im Web-Verzeichnis', () {
    expect(AppInfo.privacyUrl, endsWith('/datenschutz.html'));
    expect(AppInfo.deleteAccountUrl, endsWith('/konto-loeschen.html'));
    expect(AppInfo.impressumUrl, endsWith('/impressum.html'));
    expect(AppInfo.privacyUrlEn, endsWith('/privacy.html'));
    expect(AppInfo.deleteAccountUrlEn, endsWith('/delete-account.html'));
    expect(AppInfo.impressumUrlEn, endsWith('/imprint.html'));
    for (final p in [..._english.keys, ..._english.values]) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
  });

  test('die App öffnet die Rechtsseite in ihrer Sprache', () {
    const de = Locale('de');
    expect(AppInfo.privacyUrlFor(de), AppInfo.privacyUrl);
    expect(AppInfo.impressumUrlFor(de), AppInfo.impressumUrl);
    for (final other in const [Locale('en'), Locale('fr')]) {
      expect(AppInfo.privacyUrlFor(other), AppInfo.privacyUrlEn);
      expect(AppInfo.impressumUrlFor(other), AppInfo.impressumUrlEn);
    }
    final profile = _read('lib/features/profile/profile_screen.dart');
    expect(profile, contains('AppInfo.privacyUrlFor('));
    expect(profile, contains('AppInfo.impressumUrlFor('));
  });

  test('jede Rechtsseite verweist auf ihre andere Sprache', () {
    for (final MapEntry(key: de, value: en) in _english.entries) {
      final deName = de.split('/').last;
      final enName = en.split('/').last;
      expect(_read(de), contains('href="$enName" hreflang="en"'), reason: de);
      final html = _read(en);
      expect(html, contains('href="$deName" hreflang="de"'), reason: en);
      expect(html, contains('<html lang="en">'), reason: en);
      expect(html, contains('German version</a>'),
          reason: '$en muss sagen, dass die deutsche Fassung gilt');
    }
  });

  test('die englischen Seiten tragen dieselbe Anschrift und Adresse', () {
    final street = RegExp(r'[A-ZÄÖÜ][\wäöüß.\-]*\s?(str\.|straße|weg|platz|gasse)\s+\d+',
        caseSensitive: false);
    final zip = RegExp(r'\b\d{5}\s+[^<\s,]+(\s[^<\s,]+)?');
    final mail = RegExp(r'mailto:[^"]+');
    for (final MapEntry(key: de, value: en) in _english.entries) {
      final german = _read(de);
      final english = _read(en);
      for (final pattern in [street, zip, mail]) {
        for (final m in pattern.allMatches(german)) {
          expect(english, contains(m.group(0)), reason: '$en: ${m.group(0)}');
        }
      }
    }
  });

  test('beide Fassungen der Erklärung tragen dasselbe Datum', () {
    const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli',
      'August', 'September', 'Oktober', 'November', 'Dezember'];
    const monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
    final de = RegExp(r'Stand: (\d{1,2})\. (\S+) (\d{4})').firstMatch(_read(_privacy));
    final en = RegExp(r'As of (\d{1,2}) (\S+) (\d{4})').firstMatch(_read(_english[_privacy]!));
    expect(de, isNotNull);
    expect(en, isNotNull);
    expect(months.indexOf(de!.group(2)!), isNot(-1));
    expect('${en!.group(1)} ${en.group(2)} ${en.group(3)}',
        '${de.group(1)} ${monthsEn[months.indexOf(de.group(2)!)]} ${de.group(3)}',
        reason: 'Wer datenschutz.html ändert, zieht privacy.html nach — mit Datum');
  });

  test('das Impressum trägt eine ladungsfähige Anschrift', () {
    final html = _read(_impressum);
    expect(RegExp(r'[A-ZÄÖÜ][\wäöüß.\-]*\s?(str\.|straße|weg|platz|gasse)\s+\d',
            caseSensitive: false).hasMatch(html), isTrue);
    expect(RegExp(r'\b\d{5}\s+\S').hasMatch(html), isTrue);
    expect(html, contains('mailto:'));
  });

  test('das Impressum ist aus der App und den Nachbarseiten erreichbar', () {
    expect(_read('lib/features/profile/profile_screen.dart'), contains('AppInfo.impressumUrl'));
    expect(_read(_privacy), contains('impressum.html'));
    expect(_read(_deleteAccount), contains('impressum.html'));
    expect(_read(_english[_privacy]!), contains('imprint.html'));
    expect(_read(_english[_deleteAccount]!), contains('imprint.html'));
    for (final p in [_impressum, _privacy, ..._english.values]) {
      expect(_read(p), isNot(contains('ec.europa.eu/consumers/odr')));
    }
  });

  test('die Erklärung benennt die heiklen Punkte', () {
    final html = _read(_privacy);
    expect(html, contains('tiles.mcbuchi.de'));
    expect(html, contains('Cloudflare'));
    expect(html, contains('Orte auf der\n      Karte'),
        reason: 'die Orte liegen seit 0.18.0 auf dem Kartenhost');
    expect(html, contains('Offizielle Trails'));
    expect(html, contains('Meine Position'),
        reason: 'Standort nur nach Tipp, bleibt auf dem Gerät');
    expect(html, contains('Trail-Aufzeichnungen'));
    expect(html, contains('verlassen dein Gerät nie'),
        reason: 'Entscheidung 4 im Konzept: Fahrten bleiben lokal');
    expect(html, contains('öffentlich'));
    expect(html, contains('Konto löschen'));
    expect(html, contains('Fehlerberichte'));
    expect(html, contains('Supabase'));
    expect(html, contains('Brevo'));
    expect(html, contains('Bestätigungsmail'));
    expect(html, contains('fonts.gstatic.com'),
        reason: 'Roboto wird im Web von Google geladen (PilzBuddy #393)');
  });

  test('die englische Erklärung benennt dieselben heiklen Punkte', () {
    final html = _read(_english[_privacy]!);
    for (final what in [
      'tiles.mcbuchi.de', 'Cloudflare', 'places on the map', 'Official trails',
      'My location', 'trail recordings', 'never leave your device', 'public',
      'Delete account', 'Error reports', 'Supabase', 'Brevo',
      'confirmation email', 'fonts.gstatic.com', 'Firebase Cloud Messaging',
      'never any coordinates', 'name of the trail', 'name of the buddy',
    ]) {
      expect(html, contains(what), reason: what);
    }
  });

  test('kein neues Netzziel ohne Eintrag in der Datenschutzerklärung', () {
    /// Ziele, die die App von sich aus abruft — MÜSSEN in der Erklärung stehen.
    const fetched = {
      // Die Karte selbst (#31): das DACH-Archiv auf Cloudflare R2 — und
      // seit 0.18.0 die Orte auf der Karte (#12), je Rasterzelle eine
      // Datei, nur mit eingeschaltetem Filter.
      'tiles.mcbuchi.de',
      // Offizielle Trails (#13), Daten-Branch, nur mit eingeschalteter Ebene.
      'raw.githubusercontent.com',
      'api.github.com',
      'github.com',
      'macbuchi.github.io',
      // Das Live-Projekt (lib/core/supabase_config.dart).
      'ibxrjgvwouuoydhdkfmf.supabase.co',
    };
    /// Ziele, die erst nach dem EINSCHALTEN einer Funktion abgerufen
    /// werden — müssen trotzdem in der Erklärung stehen. Der Push-Weg
    /// (#34): Firebase im Browser lädt sein SDK von www.gstatic.com,
    /// FCM selbst liegt hinter fcm.googleapis.com (Edge Function, nicht
    /// in lib/ — hier nur, damit die Erklärung Google nennt).
    const afterConsent = {
      'www.gstatic.com',
    };
    /// Ziele, die erst der Nutzer mit einem Tipp öffnet.
    const onTapOnly = {
      'www.openstreetmap.org',
      'play.google.com',
    };
    /// Nur Text, nicht tippbar (Namensräume, Schemas).
    const textOnly = {
      'schemas.android.com',
      'www.topografix.com',
      'www.w3.org',
      'www.garmin.com',
      'www.locusmap.eu',
      'developer.mozilla.org',
      'docs.flutter.dev',
      'developer.android.com',
      'flutter.dev',
      'github.io',
    };
    final privacy = _read(_privacy);
    final hostPattern = RegExp(r'https?://([a-z0-9.-]+\.[a-z]{2,})', caseSensitive: false);
    final found = <String, Set<String>>{};
    for (final dir in ['lib', 'web']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!(f.path.endsWith('.dart') || f.path.endsWith('.js') ||
            f.path.endsWith('.html') || f.path.endsWith('.json'))) {
          continue;
        }
        if (_english.keys.contains(f.path) || _english.values.contains(f.path)) {
          continue;
        }
        for (final m in hostPattern.allMatches(f.readAsStringSync())) {
          found.putIfAbsent(m.group(1)!.toLowerCase(), () => {}).add(f.path);
        }
      }
    }
    final unknown = found.keys
        .where((h) => !fetched.contains(h) && !afterConsent.contains(h) && !onTapOnly.contains(h) && !textOnly.contains(h))
        .toList();
    expect(unknown, isEmpty,
        reason: 'Neue Hosts ohne Einordnung: ${unknown.map((h) => '$h (${found[h]!.join(', ')})').join('; ')}. '
            'In diesem Test einordnen UND, wenn abgerufen, in web/datenschutz.html erklären.');
    final privacyEn = _read(_english[_privacy]!);
    for (final h in {...fetched, ...afterConsent}) {
      expect(privacy, contains(h), reason: '$h wird abgerufen und fehlt in der Erklärung');
      expect(privacyEn, contains(h), reason: '$h fehlt in der englischen Fassung (web/privacy.html)');
    }
    expect(privacy, contains('Firebase Cloud Messaging'),
        reason: 'Push (#34) läuft über Google — die Erklärung muss es nennen');
    // Seit Patch 014 trägt eine Meldung Trailname, Alias und Hinweistext
    // (Betreiber, 2026-09-30) — nie eine Koordinate. push_flush_check.sh
    // prüft die Nutzlast, hier steht ihr Spiegel.
    expect(privacy, contains('niemals Koordinaten'),
        reason: 'die Zusage, dass keine Position über Google läuft');
    for (final what in ['Namen des Trails', 'Namen des Buddys', 'Text']) {
      expect(privacy, contains(what), reason: 'die Erklärung muss sagen, was eine Meldung trägt');
    }
  });
}
