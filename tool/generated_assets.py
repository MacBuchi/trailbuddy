#!/usr/bin/env python3
"""Frischeprüfung für erzeugte Assets (#226).

Mehrere Dateien unter `assets/` sind ERZEUGT, nicht geschrieben. CLAUDE.md
sagt das auch — „nicht von Hand editieren, sondern neu generieren" —, aber
bis hierher hielt das niemand nach. Eine Handänderung bestand jeden Check
und wurde ausgeliefert; beim nächsten Erzeugen war sie kommentarlos weg.
Dieselbe Klasse Regel wie die Patch-Buchführung oder der Version Guard:
eine Konvention, die eine Datei behauptet und kein Wächter hält.

Geprüft wird je Asset seine Prüfsumme, dazu — wo es etwas Schärferes
gibt — eine gezielte Zusatzprüfung:

- **transform_noop**: Der Kartenstil muss ein FIXPUNKT von
  `tool/transform_map_style.py` sein. Das fängt den Fall, den eine
  Prüfsumme nicht sieht: neu generiert und den Umbau vergessen. Die
  Folge wäre lautlos — vector_tile_renderer lässt Ebenen, deren
  Ausdrücke er nicht versteht, einfach weg (graue Landflächen, keine
  Beschriftung), und genau dagegen wurde das Skript geschrieben.
- **watch_talks_fixpoint**: Die Seite der Uhr des Gesprächskatalogs
  (`garmin/source/GeneratedTalks.mc`, #509) muss genau das sein, was
  `tool/watch_talks.py` aus `docs/watch_cases.json` erzeugt — sonst
  spielt die Uhr ein anderes Gespräch als das Handy.
- **self_recorded_sha256**: Das Waldgitter trägt seine Prüfsumme und
  Größe längst in `forest_manifest.json` — geschrieben vom Erzeuger,
  bis hierher von niemandem nachgerechnet. Statt die Zahl ein zweites
  Mal zu führen, wird die vorhandene geprüft.

**Warum NICHT der Hash des Erzeugers** (naheliegend, und in der
Vorlage aus DurecMix so gelöst): Er würde bei jeder Änderung an
`tool/forest_grid.py` rot werden, auch bei einem Kommentar — und ein
5,6-MB-Gitter neu zu erzeugen heißt, einen Workflow laufen zu lassen.
Nach dem dritten Fehlalarm ruft man `--update` blind auf, und dann
prüft der Wächter nichts mehr. Der Fixpunkt oben leistet dasselbe
präzise: Er wird nur rot, wenn sich die LOGIK bewegt hat.

Nach einem echten Neu-Erzeugen: `--update`, und der geänderte Manifest
gehört in denselben Commit. Das ist der Sinn — die Zeile im Diff sagt
„ja, ich habe das absichtlich neu gebaut".
"""
import argparse
import hashlib
import json
import os
import sys

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(TOOL_DIR)
MANIFEST_PATH = os.path.join(TOOL_DIR, "generated_assets.json")


def sha256_of(path):
    """Stückweise — das Waldgitter und die Basiskarte sind je einige MB."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _check_transform_noop(root, relpath, tool_relpath):
    """Ist das Asset ein Fixpunkt des Umbau-Skripts?"""
    if TOOL_DIR not in sys.path:
        sys.path.insert(0, TOOL_DIR)
    import transform_map_style

    path = os.path.join(root, relpath)
    with open(path, encoding="utf-8") as handle:
        current = handle.read()
    try:
        style = json.loads(current)
    except json.JSONDecodeError as error:
        return f"ist kein gültiges JSON mehr ({error})"
    rebuilt = transform_map_style.render(transform_map_style.transform(style))
    if rebuilt == current:
        return None
    return (f"ist kein Fixpunkt von {tool_relpath} — entweder neu "
            f"generiert, ohne den Umbau laufen zu lassen, oder der Umbau "
            f"hat sich geändert. So oder so fehlen im Renderer Ebenen, "
            f"ohne dass es jemand meldet.")


def _check_self_recorded_sha256(root, relpath, manifest_relpath):
    """Stimmt die Prüfsumme, die der Erzeuger selbst notiert hat?"""
    manifest_path = os.path.join(root, manifest_relpath)
    if not os.path.exists(manifest_path):
        return f"{manifest_relpath} fehlt — dort steht die Prüfsumme"
    with open(manifest_path, encoding="utf-8") as handle:
        recorded = json.load(handle)
    path = os.path.join(root, relpath)
    problems = []
    if recorded.get("sha256") != sha256_of(path):
        problems.append(
            f"Prüfsumme in {manifest_relpath} passt nicht zur Datei")
    size = os.path.getsize(path)
    if recorded.get("bytes") != size:
        problems.append(
            f"`bytes` in {manifest_relpath} sagt {recorded.get('bytes')}, "
            f"die Datei hat {size}")
    return "; ".join(problems) or None


def _check_watch_talks(root, relpath, tool_relpath):
    """Ist die Seite der Uhr des Gesprächskatalogs frisch erzeugt (#509)?"""
    if TOOL_DIR not in sys.path:
        sys.path.insert(0, TOOL_DIR)
    import watch_talks

    with open(os.path.join(root, "docs", "watch_cases.json"), encoding="utf-8") as handle:
        doc = json.load(handle)
    try:
        rebuilt = watch_talks.render(doc)
    except ValueError as error:
        return f"der Katalog lässt sich nicht übersetzen: {error}"
    with open(os.path.join(root, relpath), encoding="utf-8") as handle:
        if handle.read() == rebuilt:
            return None
    return (f"ist nicht das, was {tool_relpath} aus docs/watch_cases.json "
            f"erzeugt — ein Gespräch kam dazu oder änderte sich, ohne dass "
            f"die Uhr es spielt.")


EXTRA_CHECKS = {
    "transform_noop": _check_transform_noop,
    "watch_talks_fixpoint": _check_watch_talks,
    "self_recorded_sha256": _check_self_recorded_sha256,
}


def load_manifest(path=MANIFEST_PATH):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def check(root=REPO_ROOT, manifest_path=MANIFEST_PATH, out=sys.stderr):
    """Alle Einträge prüfen. Gibt die Zahl der Beanstandungen zurück."""
    manifest = load_manifest(manifest_path)
    failures = 0
    for relpath, entry in sorted(manifest["assets"].items()):
        path = os.path.join(root, relpath)
        if not os.path.exists(path):
            print(f"FEHLT: {relpath}", file=out)
            failures += 1
            continue
        problems = []
        actual = sha256_of(path)
        if actual != entry["sha256"]:
            problems.append(
                "Prüfsumme weicht ab — die Datei ist erzeugt, also wurde "
                "sie entweder von Hand geändert (dann geht die Änderung "
                "beim nächsten Erzeugen verloren) oder neu erzeugt, ohne "
                "den Manifest mitzuziehen")
        for kind, argument in (entry.get("checks") or {}).items():
            problem = EXTRA_CHECKS[kind](root, relpath, argument)
            if problem:
                problems.append(problem)
        if not problems:
            continue
        failures += 1
        print(f"\n{relpath}:", file=out)
        for problem in problems:
            print(f"  - {problem}", file=out)
        print(f"  Neu erzeugen: {entry['regenerate']}", file=out)
        print("  Danach: python3 tool/generated_assets.py --update", file=out)
    return failures


def update(root=REPO_ROOT, manifest_path=MANIFEST_PATH):
    """Die Prüfsummen neu schreiben — nach einem ECHTEN Neu-Erzeugen."""
    manifest = load_manifest(manifest_path)
    for relpath, entry in manifest["assets"].items():
        entry["sha256"] = sha256_of(os.path.join(root, relpath))
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return manifest


def self_test():
    """Netzfrei, gegen einen erfundenen Baum — prüft den Wächter, nicht
    die echten Assets. Jede Prüfung muss auch WIRKLICH anschlagen; eine,
    die nie rot wird, ist Zierde."""
    import io
    import tempfile

    if TOOL_DIR not in sys.path:
        sys.path.insert(0, TOOL_DIR)
    import transform_map_style

    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "assets"))
        plain = os.path.join(root, "assets", "plain.bin")
        with open(plain, "wb") as handle:
            handle.write(b"erzeugt, nicht geschrieben")

        # Ein Stil, der Fixpunkt IST: durch den Umbau geschickt und so
        # geschrieben, wie er dann aussieht.
        #
        # `roads_other` gehört dazu, seit der Umbau die Wanderwege-Ebenen
        # daneben setzt (1.97.0): Ohne diese Ebene BRICHT `transform`
        # bewusst ab — der echte Stil ohne sie wäre ein stilles
        # Verschwinden aller Wege.
        style_relpath = "assets/style.json"
        style = transform_map_style.transform(
            {"layers": [
                {"id": "a", "filter": ["in", ["get", "k"],
                                       ["literal", ["x"]]]},
                {"id": "roads_other", "type": "line",
                 "source-layer": "roads",
                 "filter": ["in", "kind", "other", "path"]},
            ]})
        with open(os.path.join(root, style_relpath), "w",
                  encoding="utf-8") as handle:
            handle.write(transform_map_style.render(style))

        # Ein Gitter samt selbst notierter Prüfsumme.
        grid_relpath = "assets/grid.bin"
        grid_path = os.path.join(root, grid_relpath)
        with open(grid_path, "wb") as handle:
            handle.write(b"0123456789")
        side_relpath = "assets/grid_manifest.json"
        with open(os.path.join(root, side_relpath), "w",
                  encoding="utf-8") as handle:
            json.dump({"sha256": sha256_of(grid_path), "bytes": 10}, handle)

        manifest_path = os.path.join(root, "manifest.json")
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump({"assets": {
                "assets/plain.bin": {
                    "sha256": sha256_of(plain),
                    "regenerate": "irgendein Befehl",
                },
                style_relpath: {
                    "sha256": sha256_of(os.path.join(root, style_relpath)),
                    "regenerate": "irgendein Befehl",
                    "checks": {"transform_noop": "tool/transform_map_style.py"},
                },
                grid_relpath: {
                    "sha256": sha256_of(grid_path),
                    "regenerate": "irgendein Befehl",
                    "checks": {"self_recorded_sha256": side_relpath},
                },
            }}, handle)

        quiet = io.StringIO()
        assert check(root, manifest_path, quiet) == 0, \
            f"sauberer Baum muss durchgehen:\n{quiet.getvalue()}"

        # 1. Handänderung an einer erzeugten Datei.
        with open(plain, "ab") as handle:
            handle.write(b" (mal eben angepasst)")
        assert check(root, manifest_path, io.StringIO()) == 1, \
            "eine geänderte Datei muss auffallen"
        with open(plain, "wb") as handle:
            handle.write(b"erzeugt, nicht geschrieben")

        # 2. Stil neu generiert, Umbau vergessen: moderne `in`-Syntax
        #    zurück im Filter. Der Manifest-Hash wird MITGEZOGEN, damit
        #    wirklich nur der Fixpunkt anschlägt und nicht die Prüfsumme.
        broken = {"layers": [
            {"id": "a", "filter":
             ["in", ["get", "k"], ["literal", ["x"]]]},
            {"id": "roads_other", "type": "line", "source-layer": "roads",
             "filter": ["in", "kind", "other", "path"]},
        ]}
        with open(os.path.join(root, style_relpath), "w",
                  encoding="utf-8") as handle:
            json.dump(broken, handle, ensure_ascii=False, indent=1)
        manifest = json.load(open(manifest_path, encoding="utf-8"))
        manifest["assets"][style_relpath]["sha256"] = \
            sha256_of(os.path.join(root, style_relpath))
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        report = io.StringIO()
        assert check(root, manifest_path, report) == 1, \
            "ein nicht umgebauter Stil muss auffallen"
        assert "Fixpunkt" in report.getvalue(), \
            f"und zwar über den Fixpunkt, nicht über die Prüfsumme:\n" \
            f"{report.getvalue()}"

        # 3. Selbst notierte Prüfsumme stimmt nicht mehr.
        with open(grid_path, "wb") as handle:
            handle.write(b"9876543210")
        manifest["assets"][grid_relpath]["sha256"] = sha256_of(grid_path)
        manifest["assets"][style_relpath]["sha256"] = \
            sha256_of(os.path.join(root, style_relpath))
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        report = io.StringIO()
        assert check(root, manifest_path, report) == 2, \
            "das Gitter muss neben dem Stil ebenfalls anschlagen"
        assert "Prüfsumme in assets/grid_manifest.json" in report.getvalue(), \
            report.getvalue()

    print("generated_assets self-test: ok")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="Prüfen (Rückgabe 1 bei Beanstandungen)")
    parser.add_argument("--update", action="store_true",
                        help="Prüfsummen neu schreiben — nach echtem "
                             "Neu-Erzeugen, gehört in denselben Commit")
    parser.add_argument("--self-test", action="store_true",
                        help="Netzfreier Selbsttest des Wächters")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return 0
    if args.update:
        manifest = update()
        for relpath, entry in sorted(manifest["assets"].items()):
            print(f"{entry['sha256'][:12]}  {relpath}")
        return 0
    if args.check or True:  # ohne Schalter ist Prüfen die sinnvolle Vorgabe
        failures = check()
        if failures:
            print(f"\n{failures} erzeugte(s) Asset(s) passen nicht mehr zu "
                  f"ihrer Herkunft.", file=sys.stderr)
            return 1
        print("Erzeugte Assets: alle frisch.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
