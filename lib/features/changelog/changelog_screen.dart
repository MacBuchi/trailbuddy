import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/app_colors.dart';
import '../../core/widgets/motion.dart';
import '../../l10n/l10n.dart';
import 'changelog_parser.dart';

/// Pfad der mitgelieferten Änderungsliste (Asset-Eintrag in `pubspec.yaml`).
const changelogAsset = 'CHANGELOG.md';

/// Die englische Fassung (#209). Sie beginnt mit [changelogEnglishSince];
/// ältere Versionen gibt es nur auf Deutsch, die englische Seite hängt sie
/// mit einem Hinweis an. Ab dort schreibt jeder PR seinen Block in beide
/// Dateien — `test/changelog_test.dart` wacht darüber.
const changelogAssetEn = 'CHANGELOG.en.md';

/// Die erste Version mit englischem Block.
const changelogEnglishSince = '0.120.0';

/// Zeigt die Versionshistorie aus der mitgelieferten `CHANGELOG.md`.
///
/// Die Datei liegt im Binary, die Ansicht funktioniert also ohne Empfang —
/// das ist der Unterschied zum Update-Banner, das die Release-Notes des
/// *nächsten* Updates über das Netz holt. Deshalb ist sie auch im
/// Play-Build sichtbar: Sie beschreibt die installierte App und verweist
/// auf keinen Download.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.changelogTitle)),
      body: FutureBuilder<({String de, String? en})>(
        future: _load(Localizations.localeOf(context).languageCode),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Sollte nie passieren — die Datei ist mitgeliefert. Falls doch,
            // ist eine Erklärung besser als ein leerer Bildschirm.
            return _Message(context.l10n.changelogLoadFailed);
          }
          final files = snapshot.data;
          if (files == null) {
            return const CenteredTrailLoader();
          }
          return _ChangelogBody(lines: _lines(context, files));
        },
      ),
    );
  }

  /// Deutsch allein, oder Englisch samt Deutsch für die älteren Blöcke.
  static Future<({String de, String? en})> _load(String language) async {
    final de = await rootBundle.loadString(changelogAsset);
    if (language != 'en') return (de: de, en: null);
    return (de: de, en: await rootBundle.loadString(changelogAssetEn));
  }

  static List<ChangelogLine> _lines(
      BuildContext context, ({String de, String? en}) files) {
    final de = changelogBody(parseChangelog(files.de));
    final en = files.en;
    if (en == null) return de;
    final l = context.l10n;
    return withOlderBlocks(
      changelogBody(parseChangelog(en)),
      de,
      since: changelogEnglishSince,
      title: l.changelogOlderTitle,
      note: l.changelogOlderInGerman,
    );
  }
}

class _ChangelogBody extends StatelessWidget {
  const _ChangelogBody({required this.lines});

  final List<ChangelogLine> lines;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: lines.length,
      itemBuilder: (context, index) => _ChangelogLineView(line: lines[index]),
    );
  }
}

class _ChangelogLineView extends StatelessWidget {
  const _ChangelogLineView({required this.line});

  final ChangelogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);

    switch (line.kind) {
      case ChangelogLineKind.section:
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 2),
          child: Text(
            line.text,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: AppPalette.of(context).accentText),
          ),
        );
      case ChangelogLineKind.meta:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            line.text,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        );
      case ChangelogLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: theme.textTheme.bodyMedium),
              Expanded(child: _richText(context, line)),
            ],
          ),
        );
      case ChangelogLineKind.title:
      case ChangelogLineKind.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _richText(context, line),
        );
    }
  }

  Widget _richText(BuildContext context, ChangelogLine line) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        children: [
          for (final segment in line.segments)
            TextSpan(
              text: segment.text,
              style: segment.bold
                  ? base?.copyWith(fontWeight: FontWeight.bold)
                  : base,
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}
