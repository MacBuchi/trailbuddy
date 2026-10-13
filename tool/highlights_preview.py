#!/usr/bin/env python3
"""Was zeigt das Neuheiten-Blatt nach dieser Beförderung? — für die Run-Summary.

Port von PilzBuddys `tool/highlights_preview.py` (#596 dort, #152 hier).

Das Blatt nach einem Update (#135) sucht sich seinen Inhalt SELBST: Es
zeigt die Highlights aus `kFeatureHighlights`, deren `since` neuer ist
als der Stand, den das Gerät kennt. Bei der Beförderung kuratiert niemand
etwas — und genau deshalb fällt ein vergessener Eintrag nirgends auf.
Eine große Funktion ohne Highlight kommt einfach ohne Ankündigung an.

Dieses Werkzeug sagt es an der Stelle, an der es noch etwas ändert: in
der Run-Summary von `promote.yml`, wo ohnehin jemand hinsieht. Kein Tor —
manche Beförderungen bringen ehrlich nur Korrekturen, und ein Alarm, der
dann angeht, wird weggeklickt.

Gezählt wird wie im Gerät: `since` > letzter stabiler Stand und
<= beförderte Version. Nur `HighlightKind.highlight` kommt ins Blatt;
Tipps stehen nur in „Entdecken" und werden getrennt aufgeführt.

**Abweichung von PilzBuddy: zwei Grenzen statt einer.** `planHighlights`
kennt drei Fälle, und welcher gilt, hängt am letzten stabilen Stand:

- vor `TOUR_SINCE` (0.60.0): Das Gerät hat die Karten-Tour nie gesehen,
  `planHighlights` hält es für frisch installiert — es bekommt die
  Willkommens-Tour, kein Blatt. Das ist der Stand bei der ersten
  Beförderung nach 0.46.0.
- ab `TOUR_SINCE`, vor `MEMORY_SINCE` (0.64.0): Wer die Tour gesehen hat,
  bekommt einmal den Rückblick (`kRecapLead` zuerst).
- ab `MEMORY_SINCE`: das gewöhnliche Blatt; „kein Highlight" ist dann
  ein Befund und steht als Warnung da.

**Titel seit #209 in den ARB-Dateien.** Ein Eintrag trägt
`title: (l) => l.highlight…Title`; der deutsche Text steht in
`lib/l10n/app_de.arb` DESSELBEN Stands (`--arb`). Ältere Tags haben noch
das Literal — beide Formen werden gelesen, weil `promote.yml` das
Werkzeug von main auf einen beliebigen Tag ansetzt.

`--self-test` (im Job „Analyze & Test") liest die ECHTE Datei: Zerbricht
ihr Format, wird CI rot, statt dass der Hinweis still verschwindet. Er
prüft auch, dass `promote.yml` das Werkzeug aus dem beförderten Tag
aufruft — hier und nicht in `test/`, weil der Version Guard `tool/`
ausnimmt, `test/` aber nicht, und ein Werkzeug ohne Binary-Änderung
keinen Bump braucht.
"""

import argparse
import json
import pathlib
import re
import sys

SOURCE = pathlib.Path('lib/features/highlights/feature_highlights.dart')
ARB = pathlib.Path('lib/l10n/app_de.arb')
PROMOTE = pathlib.Path('.github/workflows/promote.yml')
CI = pathlib.Path('.github/workflows/ci.yml')
SHEET_MAX = 3  # kHighlightSheetMax

# Seit dieser Version gibt es den Merker der Karten-Tour (`map_tour_seen`,
# #132). Davor hat niemand die Tour gesehen.
TOUR_SINCE = '0.60.0'

# Seit dieser Version merkt sich ein Gerät, welche Neuheiten es kennt
# (`highlights_seen_version`, #135). Wird der Merker je zurückgesetzt
# (Schlüssel mit `_2`), gehört die Version hierher.
MEMORY_SINCE = '0.64.0'

ENTRY = re.compile(
    r"FeatureHighlight\(\s*id:\s*'(?P<id>[^']+)',\s*"
    r"since:\s*'(?P<since>\d+\.\d+\.\d+)',\s*"
    r"kind:\s*HighlightKind\.(?P<kind>\w+),.*?"
    r"title:\s*(?:'(?P<title>(?:[^'\\]|\\.)*)'"
    r"|\(l\)\s*=>\s*l\.(?P<key>\w+))",
    re.S)


def version_key(v):
    return tuple(int(p) for p in v.split('.'))


def parse(text, arb=None):
    """Die Einträge; `arb` (Schlüssel → deutscher Text) löst die Titel
    auf, die seit #209 in `app_de.arb` stehen. Fehlt ein Schlüssel, steht
    er selbst da — die Summary bleibt lesbar, statt abzubrechen."""
    out = []
    for m in ENTRY.finditer(text):
        e = m.groupdict()
        key = e.pop('key')
        if key is not None:
            e['title'] = (arb or {}).get(key, key)
        else:
            e['title'] = re.sub(r"\\(.)", r'\1', e['title'])
        out.append(e)
    return out


def read_arb(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def report(entries, previous, version):
    """Markdown für die Summary."""
    lo = version_key(previous) if previous else (0, 0, 0)
    hi = version_key(version)
    new = [e for e in entries if lo < version_key(e['since']) <= hi]
    highlights = sorted((e for e in new if e['kind'] == 'highlight'),
                        key=lambda e: version_key(e['since']), reverse=True)
    tips = [e for e in new if e['kind'] == 'tip']
    since = previous or 'dem Anfang'
    out = [f'### Neuheiten-Blatt für {version}', '']
    if lo < version_key(TOUR_SINCE):
        out.append(f'Wer vom bisherigen stabilen Stand ({since}) kommt, hat '
                   'die Karten-Tour nie gesehen: Die App hält ihn für frisch '
                   'installiert und zeigt die **Willkommens-Tour**, kein '
                   'Blatt. Seither neu (alles in „Entdecken"):')
        out.append('')
        out.extend(f"- {e['title']} ({e['since']})" for e in highlights)
    elif lo < version_key(MEMORY_SINCE):
        out.append('Nutzer des bisherigen stabilen Stands, die die '
                   'Karten-Tour gesehen haben, bekommen den **Rückblick** '
                   '(einmal, `kRecapLead` zuerst) — ihre App hat sich noch '
                   'keine Version gemerkt.')
    elif not highlights:
        out.append(f'> ⚠️ **Kein Highlight seit {since}.** Das Blatt bleibt '
                   'nach dem Update aus. Stimmt das, oder fehlt ein Eintrag '
                   'in `kFeatureHighlights`?')
    else:
        out.append(f'Das Blatt zeigt (höchstens {SHEET_MAX}, jüngste zuerst):')
        out.append('')
        for i, e in enumerate(highlights):
            mark = '' if i < SHEET_MAX else ' — *nur in „Entdecken"*'
            out.append(f"- {e['title']} ({e['since']}){mark}")
    if tips:
        out.append('')
        out.append('Neue Tipps (nur in „Entdecken"): ' +
                   ', '.join(e['title'] for e in tips))
    return '\n'.join(out) + '\n'


def self_test():
    text = SOURCE.read_text(encoding='utf-8')
    arb = read_arb(ARB)
    entries = parse(text, arb)
    assert len(entries) >= 15, f'nur {len(entries)} Einträge gelesen'
    ids = [e['id'] for e in entries]
    assert len(ids) == len(set(ids)), 'doppelte Kennung gelesen'
    assert {e['kind'] for e in entries} <= {'highlight', 'tip'}
    # Jeder Eintrag beginnt mit `FeatureHighlight(` am Zeilenende — keiner
    # darf dem Muster entgehen, sonst fehlte er still in der Summary.
    declared = text.count('FeatureHighlight(\n')
    assert declared == len(entries), f'{declared} deklariert, {len(entries)} gelesen'
    unresolved = [e['id'] for e in entries if e['title'] not in arb.values()
                  and e['title'].startswith('highlight')]
    assert not unresolved, f'Titel ohne Text in app_de.arb: {unresolved}'
    assert re.search(r'kHighlightSheetMax = %d;' % SHEET_MAX, text), \
        'SHEET_MAX läuft von kHighlightSheetMax weg'

    sample = [
        {'id': 'a', 'since': '0.70.0', 'kind': 'highlight', 'title': 'A'},
        {'id': 'b', 'since': '0.72.0', 'kind': 'highlight', 'title': 'B'},
        {'id': 'c', 'since': '0.72.0', 'kind': 'tip', 'title': 'C'},
        {'id': 'd', 'since': '0.69.0', 'kind': 'highlight', 'title': 'D'},
    ]
    out = report(sample, '0.69.0', '0.72.0')
    assert '- B (0.72.0)' in out and '- A (0.70.0)' in out, out
    assert 'D (' not in out, 'der alte Stand gehört nicht dazu'
    assert out.index('- B') < out.index('- A'), 'jüngste zuerst'
    assert 'Neue Tipps' in out and 'C' in out
    assert '⚠️' in report(sample, '0.72.0', '0.72.1'), 'kein Highlight = Warnung'
    recap = report(sample, '0.61.0', '0.72.0')
    assert 'Rückblick' in recap and '⚠️' not in recap, recap
    welcome = report(sample, '0.46.0', '0.72.0')
    assert 'Willkommens-Tour' in welcome and '⚠️' not in welcome, welcome
    assert '- D (0.69.0)' in welcome, 'seither neu wird aufgezählt'
    assert 'Willkommens-Tour' in report(sample, '', '0.72.0')
    # Versionen numerisch, nicht als Text: Als Text wäre 0.100 älter
    # als 0.99.
    assert version_key('0.100.0') > version_key('0.99.0')
    assert parse("FeatureHighlight(\n  id: 'x',\n  since: '1.0.0',\n"
                 "  kind: HighlightKind.tip,\n  title: 'Dein \\'Ding\\'',"
                 )[0]['title'] == "Dein 'Ding'"
    keyed = "FeatureHighlight(\n  id: 'x',\n  since: '1.0.0',\n" \
            "  kind: HighlightKind.tip,\n  title: (l) => l.highlightXTitle,"
    assert parse(keyed, {'highlightXTitle': 'Ding'})[0]['title'] == 'Ding'
    assert parse(keyed)[0]['title'] == 'highlightXTitle', 'ohne ARB: Schlüssel'

    # Die Verdrahtung: aus dem BEFÖRDERTEN Tag lesen, nicht aus main, und
    # ab dem letzten STABILEN Stand zählen.
    promote = PROMOTE.read_text(encoding='utf-8')
    assert 'python3 tool/highlights_preview.py' in promote, \
        'promote.yml ruft die Vorschau nicht auf'
    assert 'git show "$TAG:lib/features/highlights/feature_highlights.dart"' \
        in promote, 'Vorschau liest nicht aus dem beförderten Tag'
    assert 'git show "$TAG:lib/l10n/app_de.arb"' in promote and \
        '--arb ' in promote, 'Titel nicht aus der ARB-Datei des Tags'
    assert 'select(.isPrerelease | not)' in promote, \
        'Untergrenze ist nicht der letzte stabile Stand'
    assert 'tool/highlights_preview.py --self-test' in \
        CI.read_text(encoding='utf-8'), 'Selbsttest läuft nicht in CI'
    print('ok')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--version', help='beförderte Version, ohne v')
    parser.add_argument('--since', default='', help='letzter stabiler Stand')
    parser.add_argument('--source', type=pathlib.Path, default=SOURCE)
    parser.add_argument('--arb', type=pathlib.Path, default=ARB,
                        help='app_de.arb desselben Stands (Titel seit #209)')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.version:
        parser.error('--version fehlt')
    if not args.source.exists() or args.source.stat().st_size == 0:
        print(f'### Neuheiten-Blatt für {args.version}\n\n'
              '(Keine Highlight-Liste in diesem Stand.)')
        return
    entries = parse(args.source.read_text(encoding='utf-8'),
                    read_arb(args.arb))
    sys.stdout.write(report(entries, args.since.lstrip('v'), args.version))


if __name__ == '__main__':
    main()
