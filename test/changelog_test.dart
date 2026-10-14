// Wacht über die ausgelieferte Änderungsliste. Der wichtigste Test ist der
// letzte: Eine Version, die veröffentlicht wird, ohne in CHANGELOG.md
// aufzutauchen, macht die Liste in der App still unvollständig — und genau
// das passiert, wenn niemand daran erinnert wird.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/changelog/changelog_parser.dart';
import 'package:trailbuddy/features/changelog/changelog_screen.dart';
import 'package:trailbuddy/l10n/app_localizations.dart';

String _changelog([String asset = changelogAsset]) {
  final file = File(asset);
  expect(file.existsSync(), isTrue, reason: '$asset fehlt');
  return file.readAsStringSync();
}

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version =
      RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
  expect(version, isNotNull, reason: 'version fehlt in pubspec.yaml');
  return version!;
}

/// Alle Versionen aus den Metazeilen ab [since].
Set<String> _versionsSince(String markdown, String since) => {
      for (final line in parseChangelog(markdown))
        if (line.kind == ChangelogLineKind.meta)
          for (final v in metaVersions(line.text))
            if (compareVersions(v, since) >= 0) v,
    };

void main() {
  group('Parser', () {
    test('erkennt Überschrift, Metazeile, Absatz und Aufzählung', () {
      final lines = parseChangelog('''
# Titel

## Ein Block

*2. August 2026 · Version 1.33.0*

Ein Absatz, der über
zwei Zeilen umgebrochen ist.

- Ein Punkt
- Noch einer
''');

      expect(lines.map((l) => l.kind), [
        ChangelogLineKind.title,
        ChangelogLineKind.section,
        ChangelogLineKind.meta,
        ChangelogLineKind.text,
        ChangelogLineKind.bullet,
        ChangelogLineKind.bullet,
      ]);
      expect(lines[1].text, 'Ein Block');
      expect(lines[2].text, '2. August 2026 · Version 1.33.0');
      // Umbruch innerhalb des Absatzes wird zusammengefasst, sonst bräche
      // der Text auf dem Handy an den Stellen der Datei statt am Rand.
      expect(lines[3].text, 'Ein Absatz, der über zwei Zeilen umgebrochen ist.');
      expect(lines[5].text, 'Noch einer');
    });

    test('trennt **fett** heraus und lässt unpaarige Sternchen stehen', () {
      final bold = parseChangelog('**Behoben:** Die Karte blieb leer.').single;
      expect(bold.segments.map((s) => s.bold), [true, false]);
      expect(bold.segments.first.text, 'Behoben:');
      expect(bold.text, 'Behoben: Die Karte blieb leer.');

      // Ein einzelnes ** darf nicht den Rest der Zeile verschlucken.
      final broken = parseChangelog('Ein **halb offener Text').single;
      expect(broken.text, 'Ein **halb offener Text');
      expect(broken.segments.every((s) => !s.bold), isTrue);
    });

    test('vergleicht Versionen als Zahlen', () {
      expect(compareVersions('0.99.0', '0.100.0'), lessThan(0));
      expect(compareVersions('0.120.0', '0.120.0'), 0);
      expect(compareVersions('1.0.0', '0.200.9'), greaterThan(0));
      expect(metaVersions('Versionen 0.117.0 bis 0.117.5, 2026-10-13'),
          ['0.117.0', '0.117.5']);
    });

    test('blocksBefore nimmt nur Blöcke ganz unter der Version', () {
      final body = changelogBody(parseChangelog('''
# Titel

## Neu

*Version 0.120.0, 2026-10-14*

- neu

## Über die Grenze

*Versionen 0.119.0 bis 0.120.1, 2026-10-14*

- beides

## Alt

*Version 0.119.0, 2026-10-13*

- alt

## Unter der Haube

- ohne Versionen
'''));
      expect(blocksBefore(body, '0.120.0').map((l) => l.text),
          ['Alt', 'Version 0.119.0, 2026-10-13', 'alt']);
    });

    test('hält eine fett beginnende Zeile nicht für die Metazeile', () {
      // `*…*` und `**…**` unterscheiden sich nur im zweiten Zeichen.
      final line = parseChangelog('**Behoben:** etwas*').single;
      expect(line.kind, ChangelogLineKind.text);
    });
  });

  for (final asset in [changelogAsset, changelogAssetEn]) {
  group('Die ausgelieferte Datei $asset', () {
    test('besteht aus Themenblöcken mit Datums- und Versionszeile', () {
      final lines = parseChangelog(_changelog(asset));
      final sections = lines
          .where((l) => l.kind == ChangelogLineKind.section)
          .toList();
      expect(sections, isNotEmpty,
          reason: 'Die Liste soll nach Themen gegliedert sein');

      // Jeder Block außer „Unter der Haube" (ohne Versionen) nennt Datum
      // und Versionen — ohne die lässt sich ein Eintrag keiner
      // installierten App zuordnen.
      for (var i = 0; i < lines.length - 1; i++) {
        if (lines[i].kind != ChangelogLineKind.section) continue;
        if (lines[i].text == 'Unter der Haube') continue;
        expect(lines[i + 1].kind, ChangelogLineKind.meta,
            reason: 'Block „${lines[i].text}" hat keine Datums-/Versionszeile');
      }
    });

    test('enthält keine Markdown-Links', () {
      // Die App rendert nur Überschriften, Aufzählungen und **fett** — ein
      // `[Text](URL)` stünde dort roh auf dem Bildschirm.
      expect(RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(_changelog(asset)),
          isFalse,
          reason: 'Nackte URL schreiben statt [Text](URL)');
    });

    test('nennt die aktuelle Version aus pubspec.yaml', () {
      // Wer die Version hochsetzt, trägt sie hier ein — entweder als neuer
      // Block oder indem er den obersten Block darauf erweitert. Ohne
      // diesen Test fällt eine vergessene Zeile erst auf, wenn jemand in
      // der App nachsieht.
      final version = _pubspecVersion();
      expect(_changelog(asset), contains(version),
          reason: 'Version $version steht in pubspec.yaml, aber nicht in '
              '$asset. Neuen Block anlegen oder den obersten Block '
              'auf diese Version erweitern.');
    });
  });
  }

  test('ab $changelogEnglishSince nennen beide Sprachen dieselben Versionen',
      () {
    // Betreiber 2026-10-13 (#209): Ab der englischen Liste schreibt jeder PR
    // seinen Block in beiden Sprachen. Fehlt einer, sähe die englische App
    // die Neuerung nie — sie liest die deutschen Blöcke erst unterhalb von
    // changelogEnglishSince.
    final de = _versionsSince(_changelog(), changelogEnglishSince);
    final en = _versionsSince(_changelog(changelogAssetEn), changelogEnglishSince);
    expect(en, de,
        reason: 'CHANGELOG.md und $changelogAssetEn nennen ab '
            '$changelogEnglishSince verschiedene Versionen');
    expect(de, contains(changelogEnglishSince));
  });

  group('Die Seite', () {
    // rootBundle merkt sich das Future je Datei — eins aus einem früheren
    // Test hängt an dessen Zone und meldet sich im nächsten nie.
    setUp(rootBundle.clear);

    Future<void> pumpIn(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const ChangelogScreen(),
      ));
      // rootBundle liest echt von der Platte — außerhalb der Fake-Zeit
      // warten, bis die Liste steht.
      for (var i = 0; i < 200 && find.byType(ListView).evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.byType(ListView), findsOneWidget);
    }

    String firstSection(String asset) => changelogBody(
            parseChangelog(_changelog(asset)))
        .first
        .text;

    testWidgets('auf Englisch: oben der neueste englische Block',
        (tester) async {
      await pumpIn(tester, const Locale('en'));
      expect(find.text(firstSection(changelogAssetEn)), findsOneWidget);
      expect(find.text(firstSection(changelogAsset)), findsNothing,
          reason: 'Der neueste deutsche Block hat ein englisches Gegenstück');
    });

    test('auf Englisch: nach den englischen Blöcken Hinweis und die alten',
        () {
      final en = changelogBody(parseChangelog(_changelog(changelogAssetEn)));
      final de = changelogBody(parseChangelog(_changelog()));
      final texts = withOlderBlocks(en, de,
              since: changelogEnglishSince, title: 'T', note: 'N')
          .map((l) => l.text)
          .toList();
      final title = texts.indexOf('T');
      expect(title, en.length);
      expect(texts[title + 1], 'N');
      // Der erste deutsche Block danach liegt ganz vor der englischen Liste.
      final firstOld = texts[title + 2];
      expect(en.map((l) => l.text), isNot(contains(firstOld)));
      expect(texts, contains('Trails ohne Namen'));
      expect(texts.where((t) => t == 'Datenschutz und Impressum auf Englisch'),
          isEmpty,
          reason: 'Blöcke ab $changelogEnglishSince stehen nur englisch da');
    });

    testWidgets('auf Deutsch: nur die deutsche Liste, kein Hinweis',
        (tester) async {
      await pumpIn(tester, const Locale('de'));
      expect(find.text(firstSection(changelogAsset)), findsOneWidget);
      expect(find.text('Frühere Versionen'), findsNothing);
    });
  });
}
