import 'dart:convert';

/// Liest die mitgelieferte `CHANGELOG.md` in eine Liste von Zeilen, die
/// sich anzeigen lässt.
///
/// Bewusst kein Markdown-Paket: Die Datei ist unsere eigene und hält sich
/// an einen kleinen, festen Umfang — Überschriften, eine kursive Zeile mit
/// Datum und Versionen, Absätze, Aufzählungen und **fett**. Ein
/// vollständiger Renderer wäre eine zusätzliche Abhängigkeit für Syntax,
/// die in dieser Datei nie vorkommt. Wer die Datei erweitert, hält sich an
/// diesen Umfang — alles andere landet als schlichter
/// Text auf dem Bildschirm.
///
/// Links in `[Text](URL)`-Schreibweise gehören deshalb NICHT hinein; nackte
/// URLs macht GitHub von selbst klickbar und die App zeigt sie lesbar an.
enum ChangelogLineKind {
  /// `# …` — Titel der Datei.
  title,

  /// `## …` — Überschrift eines Themenblocks.
  section,

  /// `*…*` — Datum und Versionen unter der Überschrift.
  meta,

  /// Fließtext.
  text,

  /// `- …` — Punkt einer Aufzählung.
  bullet,
}

/// Ein Stück einer Zeile — normal oder fett.
class ChangelogSegment {
  const ChangelogSegment(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

/// Eine gerenderte Zeile: ihre Art und ihr in Segmente zerlegter Text.
class ChangelogLine {
  const ChangelogLine(this.kind, this.segments);

  final ChangelogLineKind kind;
  final List<ChangelogSegment> segments;

  /// Der Text ohne Auszeichnung — für Tests und Suche.
  String get text => segments.map((s) => s.text).join();
}

/// Zerlegt den Dateiinhalt. Umbrüche innerhalb eines Absatzes oder
/// Aufzählungspunktes werden zusammengefasst: Die Datei ist auf 75 Zeichen
/// umgebrochen, damit sie sich auf GitHub gut liest — auf dem Handy soll
/// derselbe Absatz aber frei umbrechen dürfen.
List<ChangelogLine> parseChangelog(String markdown) {
  final result = <ChangelogLine>[];
  final buffer = StringBuffer();
  ChangelogLineKind? open;

  void flush() {
    final kind = open;
    if (kind == null) return;
    final text = buffer.toString().trim();
    if (text.isNotEmpty) result.add(ChangelogLine(kind, _segments(text)));
    buffer.clear();
    open = null;
  }

  void single(ChangelogLineKind kind, String text) {
    flush();
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) result.add(ChangelogLine(kind, _segments(trimmed)));
  }

  for (final raw in const LineSplitter().convert(markdown)) {
    final line = raw.trim();

    // Leerzeile beendet den laufenden Absatz.
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('## ')) {
      single(ChangelogLineKind.section, line.substring(3));
      continue;
    }
    if (line.startsWith('# ')) {
      single(ChangelogLineKind.title, line.substring(2));
      continue;
    }
    if (line.startsWith('- ')) {
      flush();
      open = ChangelogLineKind.bullet;
      buffer.write(line.substring(2));
      continue;
    }
    // Kursive Zeile (Datum + Versionen) — nur, wenn sie allein steht;
    // `**fett**` am Zeilenanfang ist etwas anderes.
    if (open == null &&
        line.length > 2 &&
        line.startsWith('*') &&
        !line.startsWith('**') &&
        line.endsWith('*')) {
      single(ChangelogLineKind.meta, line.substring(1, line.length - 1));
      continue;
    }

    // Fortsetzung des laufenden Absatzes bzw. Beginn eines neuen.
    open ??= ChangelogLineKind.text;
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(line);
  }
  flush();

  return result;
}

/// Trennt `**fett**` heraus. Unpaarige Sternchen bleiben stehen, statt den
/// Rest der Zeile zu verschlucken.
List<ChangelogSegment> _segments(String text) {
  final segments = <ChangelogSegment>[];
  var rest = text;

  while (true) {
    final start = rest.indexOf('**');
    if (start < 0) break;
    final end = rest.indexOf('**', start + 2);
    if (end < 0) break;
    if (start > 0) segments.add(ChangelogSegment(rest.substring(0, start)));
    segments.add(ChangelogSegment(rest.substring(start + 2, end), bold: true));
    rest = rest.substring(end + 2);
  }
  if (rest.isNotEmpty) segments.add(ChangelogSegment(rest));

  return segments;
}

/// Alles ab der ersten Blocküberschrift. Titel und Vorspann der Datei
/// richten sich an Leser auf GitHub und erklären unter anderem den Weg zu
/// genau dem Bildschirm, der sie zeigt.
List<ChangelogLine> changelogBody(List<ChangelogLine> lines) => lines
    .skipWhile((line) => line.kind != ChangelogLineKind.section)
    .toList();

final _version = RegExp(r'\b(\d+)\.(\d+)\.(\d+)\b');

/// Die Versionen, die eine Metazeile nennt („Versionen 0.117.0 bis
/// 0.117.5, …" ⇒ beide).
List<String> metaVersions(String meta) =>
    _version.allMatches(meta).map((m) => m.group(0)!).toList();

/// Vergleicht `MAJOR.MINOR.PATCH` numerisch (0.99.0 < 0.100.0).
int compareVersions(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Die Blöcke aus [body], deren höchste Version unter [version] liegt —
/// für die englische Liste die deutschen Blöcke vor ihrem Anfang (#209).
/// Ein Block ohne Metazeile („Unter der Haube") gehört nicht dazu.
List<ChangelogLine> blocksBefore(List<ChangelogLine> body, String version) {
  final result = <ChangelogLine>[];
  var keep = false;
  for (var i = 0; i < body.length; i++) {
    final line = body[i];
    if (line.kind == ChangelogLineKind.section) {
      final next = i + 1 < body.length ? body[i + 1] : null;
      final versions = next?.kind == ChangelogLineKind.meta
          ? metaVersions(next!.text)
          : const <String>[];
      keep = versions.isNotEmpty &&
          versions.every((v) => compareVersions(v, version) < 0);
    }
    if (keep) result.add(line);
  }
  return result;
}

/// Die Liste einer Übersetzung, die erst bei [since] beginnt: ihre Blöcke,
/// dann Überschrift [title] und Hinweis [note], dann die Blöcke des
/// Originals [de] vor [since].
List<ChangelogLine> withOlderBlocks(
  List<ChangelogLine> translated,
  List<ChangelogLine> de, {
  required String since,
  required String title,
  required String note,
}) =>
    [
      ...translated,
      ChangelogLine(ChangelogLineKind.section, [ChangelogSegment(title)]),
      ChangelogLine(ChangelogLineKind.text, [ChangelogSegment(note)]),
      ...blocksBefore(de, since),
    ];
