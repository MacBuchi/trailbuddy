#!/usr/bin/env python3
"""Inventory of the R2 bucket (#230): sizes, stale builds, duplicates.

Four workflows write dated builds plus a small manifest under the
`trailbuddy/` prefix of the bucket `buddy-tiles`, and each removes what is
older than the two newest builds of its own family:

    map-data.yml     dach.json     -> dach-<build>.pmtiles
    height-data.yml  heights.json  -> heights-<build>.pmtiles
    way-data.yml     ways.json     -> ways-<build>.pmtiles
    poi-data.yml     pois.json     -> pois-<build>/   (one file per cell)

Nothing checked until now whether that holds: a run that uploads and
stops before its manifest leaves a build nobody names, and "the two
newest" is not "the current one and the one before" once that happened.
This tool reads a listing of the whole bucket and the manifests and
says, per family, which build is current, which is kept for sessions in
flight, which is stale or orphaned — plus what lies in the prefix that no
family claims, unfinished multipart uploads, objects stored twice
(same size and ETag) and the total against R2's free storage.

It never writes or deletes. The listing comes from the AWS CLI in
r2-inventory.yml (the same client the data workflows use):

    aws s3api list-objects-v2 --bucket B --output json > listing.json
    aws s3api list-multipart-uploads --bucket B --output json > uploads.json
    python3 tool/r2_inventory.py report --listing listing.json \\
        --uploads uploads.json --manifests build/manifests [--json out.json]
    python3 tool/r2_inventory.py --self-test      # no network

The report goes to the run summary. It names keys and sizes, nothing
else — the bucket holds only public data (concept 7). Exit code 1 only
when a manifest names something the bucket does not hold in full: that
is a broken app, not housekeeping.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import sys
import tempfile
from collections import defaultdict

PREFIX = "trailbuddy"
# R2 free tier: 10 GB-month of storage (concept-offline-karten 7).
FREE_STORAGE_BYTES = 10 * 1000 ** 3

# One row per family: manifest name, the key pattern of a build (group 1
# is the build), the manifest field that names the current build's key,
# and whether a build is a single object or a folder of objects.
FAMILIES = (
    {"name": "map", "workflow": "map-data.yml", "manifest": "dach.json",
     "pattern": re.compile(r"^(dach-(\d{8})\.pmtiles)$"), "field": "file", "folder": False},
    {"name": "heights", "workflow": "height-data.yml", "manifest": "heights.json",
     "pattern": re.compile(r"^(heights-(\d{8})\.pmtiles)$"), "field": "file", "folder": False},
    {"name": "ways", "workflow": "way-data.yml", "manifest": "ways.json",
     "pattern": re.compile(r"^(ways-(\d{8})\.pmtiles)$"), "field": "file", "folder": False},
    {"name": "places", "workflow": "poi-data.yml", "manifest": "pois.json",
     "pattern": re.compile(r"^(pois-(\d{8}))/.+$"), "field": "prefix", "folder": True},
)


def load_objects(listing: dict) -> list[dict]:
    """`list-objects-v2` JSON -> [{key, size, etag}]. An empty bucket has
    no `Contents` at all (and the CLI may print nothing)."""
    objects = []
    for item in (listing or {}).get("Contents") or []:
        objects.append({
            "key": item["Key"],
            "size": int(item.get("Size", 0)),
            "etag": str(item.get("ETag", "")).strip('"'),
        })
    return objects


def load_uploads(uploads: dict) -> list[dict]:
    return [{"key": u.get("Key", ""), "initiated": u.get("Initiated", "")}
            for u in (uploads or {}).get("Uploads") or []]


def read_json(path: str):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def analyse(objects: list[dict], uploads: list[dict], manifests: dict,
            prefix: str = PREFIX) -> dict:
    """Everything the report says, as data. `manifests` maps a manifest
    name to its parsed content, or None when it is not in the bucket."""
    base = prefix.rstrip("/") + "/"
    ours = [o for o in objects if o["key"].startswith(base)]
    foreign = defaultdict(lambda: {"objects": 0, "bytes": 0})
    for o in objects:
        if not o["key"].startswith(base):
            top = o["key"].split("/", 1)[0] + ("/" if "/" in o["key"] else "")
            foreign[top]["objects"] += 1
            foreign[top]["bytes"] += o["size"]

    manifest_names = {f["manifest"] for f in FAMILIES}
    claimed = set()
    families = []
    errors = []
    for fam in FAMILIES:
        builds = defaultdict(lambda: {"objects": 0, "bytes": 0})
        unit_of = {}
        for o in ours:
            rel = o["key"][len(base):]
            m = fam["pattern"].match(rel)
            if not m:
                continue
            claimed.add(o["key"])
            build = m.group(2)
            builds[build]["objects"] += 1
            builds[build]["bytes"] += o["size"]
            builds[build]["unit"] = m.group(1)
            unit_of[o["key"]] = f"{fam['name']} {build}"
        manifest = manifests.get(fam["manifest"])
        current = None
        if manifest is None:
            if builds:
                errors.append(f"{fam['manifest']} is missing, but {len(builds)} "
                              f"{fam['name']} build(s) lie in the bucket")
        else:
            named = str(manifest.get(fam["field"], ""))
            m = fam["pattern"].match(named + ("/x" if fam["folder"] else ""))
            if not m:
                errors.append(f"{fam['manifest']}: `{fam['field']}` is `{named}`, "
                              f"not a {fam['name']} build name")
            else:
                # A named build the bucket lacks is no reference point:
                # "stale" or "orphan" against it would be guesses.
                held = builds.get(m.group(2))
                if held is None:
                    errors.append(f"{fam['manifest']} names `{named}`, which is NOT in the bucket")
                else:
                    current = m.group(2)
                    want_bytes = manifest.get("bytes")
                    if want_bytes is not None and int(want_bytes) != held["bytes"]:
                        errors.append(f"{fam['manifest']}: `{named}` holds {held['bytes']} "
                                      f"bytes, the manifest says {want_bytes}")
                    want_files = manifest.get("files") if fam["folder"] else 1
                    if want_files is not None and int(want_files) != held["objects"]:
                        errors.append(f"{fam['manifest']}: `{named}` holds {held['objects']} "
                                      f"objects, the manifest says {want_files}")
        ordered = sorted(builds)
        previous = None
        if current is not None:
            older = [b for b in ordered if b < current]
            previous = older[-1] if older else None
        rows = []
        for b in ordered:
            if b == current:
                state = "current"
            elif b == previous:
                state = "previous"
            elif current is None:
                state = "unnamed"
            elif b > current:
                state = "orphan"
            else:
                state = "stale"
            rows.append({"build": b, "unit": builds[b]["unit"], "state": state,
                         "objects": builds[b]["objects"], "bytes": builds[b]["bytes"]})
        families.append({
            "name": fam["name"], "workflow": fam["workflow"], "manifest": fam["manifest"],
            "manifest_present": manifest is not None, "current": current,
            "builds": rows, "unit_of": unit_of,
        })

    unknown = []
    for o in ours:
        rel = o["key"][len(base):]
        if o["key"] in claimed or rel in manifest_names:
            continue
        unknown.append({"key": o["key"], "bytes": o["size"]})

    # Same size AND same ETag: the same bytes under two keys. For a
    # multipart upload the ETag is "<md5 of part md5s>-<parts>", equal
    # only for the same bytes cut into the same parts — the CLI's default
    # part size, so a match is still a match; a miss could hide a twin.
    unit_of = {}
    for fam in families:
        unit_of.update(fam.pop("unit_of"))
    groups = defaultdict(list)
    for o in objects:
        if o["size"] > 0 and o["etag"]:
            groups[(o["size"], o["etag"])].append(o["key"])
    dup_by_units = defaultdict(lambda: {"groups": 0, "extra_objects": 0, "extra_bytes": 0})
    for (size, _), keys in groups.items():
        if len(keys) < 2:
            continue
        units = tuple(sorted({unit_of.get(k, "other " + k.split("/", 1)[0]) for k in keys}))
        entry = dup_by_units[units]
        entry["groups"] += 1
        entry["extra_objects"] += len(keys) - 1
        entry["extra_bytes"] += size * (len(keys) - 1)
    duplicates = sorted(({"units": list(u), **v} for u, v in dup_by_units.items()),
                        key=lambda d: -d["extra_bytes"])

    total = sum(o["size"] for o in objects)
    return {
        "prefix": base,
        "objects": len(objects),
        "bytes": total,
        "prefix_bytes": sum(o["size"] for o in ours),
        "free_bytes": FREE_STORAGE_BYTES,
        "families": families,
        "unknown": sorted(unknown, key=lambda u: -u["bytes"]),
        "foreign": [{"prefix": k, **v} for k, v in sorted(foreign.items())],
        "uploads": uploads,
        "duplicates": duplicates,
        "errors": errors,
    }


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1000
    return f"{n:.1f} GB"


STATE_TEXT = {
    "current": "current — the manifest names it",
    "previous": "previous — kept for sessions in flight",
    "stale": "**stale** — older than the previous build; retention should have removed it",
    "orphan": "**orphan** — newer than the manifest; a run uploaded and stopped before the manifest",
    "unnamed": "**unnamed** — the manifest names no build the bucket holds",
}


def render(result: dict, bucket: str = "buddy-tiles") -> str:
    lines = [f"## R2 inventory: `{bucket}`", ""]
    share = result["bytes"] / result["free_bytes"] * 100
    lines.append(f"- {result['objects']} objects, {human(result['bytes'])} in the bucket "
                 f"({share:.0f} % of the {human(result['free_bytes'])} free storage); "
                 f"`{result['prefix']}` holds {human(result['prefix_bytes'])}")
    reclaim = sum(b["bytes"] for f in result["families"] for b in f["builds"]
                  if b["state"] in ("stale", "orphan"))
    reclaim += sum(u["bytes"] for u in result["unknown"])
    lines.append(f"- reclaimable (stale, orphaned and unclaimed objects): {human(reclaim)}")
    lines.append("")
    if result["errors"]:
        lines.append("### Errors — the app reads a broken state")
        lines += [f"- {e}" for e in result["errors"]]
        lines.append("")

    lines += ["### Builds per family", "",
              "| family | build | objects | size | state |", "|---|---|---:|---:|---|"]
    for fam in result["families"]:
        if not fam["builds"]:
            note = "no manifest" if not fam["manifest_present"] else "manifest, no build"
            lines.append(f"| {fam['name']} (`{fam['manifest']}`) | — | 0 | — | {note} |")
            continue
        for b in fam["builds"]:
            lines.append(f"| {fam['name']} | `{b['unit']}` | {b['objects']} | {human(b['bytes'])} "
                         f"| {STATE_TEXT[b['state']]} |")
    lines.append("")
    lines.append("Per family the current build is what a new region of the map costs in "
                 "storage; the base for measuring beyond DACH (#220).")
    lines.append("")

    lines.append("### Stored twice (same size and ETag)")
    lines.append("")
    if not result["duplicates"]:
        lines.append("None.")
    else:
        lines += ["| between | groups | extra objects | extra bytes |", "|---|---:|---:|---:|"]
        for d in result["duplicates"][:15]:
            lines.append(f"| {' · '.join(d['units'])} | {d['groups']} | {d['extra_objects']} "
                         f"| {human(d['extra_bytes'])} |")
        if len(result["duplicates"]) > 15:
            lines.append(f"| … {len(result['duplicates']) - 15} more | | | |")
        lines.append("")
        lines.append("Twins between the current and the previous build of one family are "
                     "expected where the source did not change (the DEM is static, most "
                     "place cells stay the same); they go when the older build goes.")
    lines.append("")

    lines.append(f"### In `{result['prefix']}` but no family's")
    lines.append("")
    if not result["unknown"]:
        lines.append("None.")
    else:
        for u in result["unknown"][:40]:
            lines.append(f"- `{u['key']}` ({human(u['bytes'])})")
        if len(result["unknown"]) > 40:
            lines.append(f"- … {len(result['unknown']) - 40} more")
    lines.append("")

    if result["foreign"]:
        lines.append("### Other prefixes (not TrailBuddy's, not judged)")
        lines.append("")
        for f in result["foreign"]:
            lines.append(f"- `{f['prefix']}`: {f['objects']} objects, {human(f['bytes'])}")
        lines.append("")

    lines.append("### Unfinished multipart uploads")
    lines.append("")
    if not result["uploads"]:
        lines.append("None.")
    else:
        lines.append("Their parts are stored until the upload is aborted (bucket lifecycle "
                     "rule or `aws s3api abort-multipart-upload`).")
        for u in result["uploads"]:
            lines.append(f"- `{u['key']}` since {u['initiated']}")
    lines.append("")
    lines.append("Read only: this run lists and reads, it removes nothing.")
    return "\n".join(lines) + "\n"


def self_test():
    def obj(key, size, etag):
        return {"Key": key, "Size": size, "ETag": f'"{etag}"'}

    listing = {"Contents": [
        obj("trailbuddy/dach.json", 400, "m1"),
        obj("trailbuddy/dach-20260901.pmtiles", 100, "a1"),          # stale
        obj("trailbuddy/dach-20260928.pmtiles", 110, "a2"),          # previous
        obj("trailbuddy/dach-20261001.pmtiles", 120, "a3-24"),       # current
        obj("trailbuddy/dach-20261005.pmtiles", 120, "a3-24"),       # orphan, twin of current
        obj("trailbuddy/heights.json", 300, "m2"),
        obj("trailbuddy/heights-20261001.pmtiles", 50, "h1"),
        obj("trailbuddy/heights-20261008.pmtiles", 50, "h1"),        # identical DEM build
        obj("trailbuddy/pois.json", 900, "m3"),
        obj("trailbuddy/pois-20261002/475,60.food.json", 7, "c1"),
        obj("trailbuddy/pois-20261002/475,61.food.json", 8, "c2"),
        obj("trailbuddy/pois-20261009/475,60.food.json", 7, "c1"),   # unchanged cell
        obj("trailbuddy/pois-20261009/475,61.food.json", 9, "c3"),
        obj("trailbuddy/test.pmtiles", 33, "t1"),                    # nobody's
        obj("pilzbuddy/x.pmtiles", 44, "p1"),                        # foreign prefix
    ]}
    uploads = {"Uploads": [{"Key": "trailbuddy/dach-20261007.pmtiles",
                            "Initiated": "2026-10-07T03:20:00Z", "UploadId": "u"}]}
    manifests = {
        "dach.json": {"file": "dach-20261001.pmtiles", "bytes": 120},
        "heights.json": {"file": "heights-20261008.pmtiles", "bytes": 50},
        "ways.json": None,
        "pois.json": {"prefix": "pois-20261009", "files": 2, "bytes": 16},
    }
    r = analyse(load_objects(listing), load_uploads(uploads), manifests)
    fam = {f["name"]: f for f in r["families"]}
    states = {b["build"]: b["state"] for b in fam["map"]["builds"]}
    assert states == {"20260901": "stale", "20260928": "previous",
                      "20261001": "current", "20261005": "orphan"}, states
    assert [b["state"] for b in fam["heights"]["builds"]] == ["previous", "current"]
    places = {b["build"]: (b["state"], b["objects"], b["bytes"]) for b in fam["places"]["builds"]}
    assert places == {"20261002": ("previous", 2, 15), "20261009": ("current", 2, 16)}, places
    assert fam["ways"]["builds"] == [] and not fam["ways"]["manifest_present"]
    assert r["errors"] == [], r["errors"]
    assert r["unknown"] == [{"key": "trailbuddy/test.pmtiles", "bytes": 33}], r["unknown"]
    assert r["foreign"] == [{"prefix": "pilzbuddy/", "objects": 1, "bytes": 44}], r["foreign"]
    dups = {tuple(d["units"]): d for d in r["duplicates"]}
    assert dups[("map 20261001", "map 20261005")]["extra_bytes"] == 120, dups
    assert dups[("heights 20261001", "heights 20261008")]["extra_objects"] == 1
    assert dups[("places 20261002", "places 20261009")]["extra_bytes"] == 7
    assert r["duplicates"][0]["units"] == ["map 20261001", "map 20261005"]  # largest first
    text = render(r)
    assert "**stale**" in text and "**orphan**" in text and "Errors" not in text
    assert "reclaimable (stale, orphaned and unclaimed objects): 253 B" in text, text
    assert "`trailbuddy/dach-20261007.pmtiles` since 2026-10-07T03:20:00Z" in text

    # The manifest names a build the bucket does not hold in full: an error.
    broken = dict(manifests)
    broken["dach.json"] = {"file": "dach-20261003.pmtiles", "bytes": 120}
    broken["heights.json"] = {"file": "heights-20261008.pmtiles", "bytes": 51}
    broken["pois.json"] = {"prefix": "pois-20261009", "files": 3, "bytes": 16}
    r = analyse(load_objects(listing), [], broken)
    assert len(r["errors"]) == 3, r["errors"]
    assert "NOT in the bucket" in r["errors"][0]
    assert "holds 50 bytes, the manifest says 51" in r["errors"][1]
    assert "holds 2 objects, the manifest says 3" in r["errors"][2]
    # With no build named, nothing is called stale or orphaned.
    assert {b["state"] for b in next(f for f in r["families"] if f["name"] == "map")["builds"]} \
        == {"unnamed"}
    # A missing manifest with builds left behind is an error, too.
    r = analyse(load_objects(listing), [], {**manifests, "heights.json": None})
    assert any("heights.json is missing" in e for e in r["errors"]), r["errors"]
    # A name that is no build of the family is an error, not a crash.
    r = analyse(load_objects(listing), [], {**manifests, "pois.json": {"prefix": "x"}})
    assert any("not a places build name" in e for e in r["errors"]), r["errors"]

    # Empty bucket: the CLI prints nothing at all.
    r = analyse(load_objects(None), load_uploads(None), {f["manifest"]: None for f in FAMILIES})
    assert r["objects"] == 0 and r["errors"] == [] and r["duplicates"] == []
    assert "None." in render(r)

    # The command line end to end: files in, report out, exit 1 on errors.
    with tempfile.TemporaryDirectory() as tmp:
        lpath = os.path.join(tmp, "listing.json")
        upath = os.path.join(tmp, "uploads.json")
        mdir = os.path.join(tmp, "manifests")
        os.makedirs(mdir)
        with open(lpath, "w") as h:
            json.dump(listing, h)
        open(upath, "w").close()  # list-multipart-uploads prints nothing when none
        for name, content in manifests.items():
            if content is not None:
                with open(os.path.join(mdir, name), "w") as h:
                    json.dump(content, h)
        jpath = os.path.join(tmp, "out.json")
        with contextlib.redirect_stdout(io.StringIO()):
            assert main(["report", "--listing", lpath, "--uploads", upath,
                         "--manifests", mdir, "--json", jpath]) == 0
        assert json.load(open(jpath))["objects"] == 15
        with open(os.path.join(mdir, "dach.json"), "w") as h:
            json.dump(broken["dach.json"], h)
        # Quietly: an `::error::` from the self-test would be a red
        # annotation on every CI run.
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()) as err:
            assert main(["report", "--listing", lpath, "--manifests", mdir]) == 1
        assert "::error::dach.json names" in err.getvalue(), err.getvalue()
    # The workflow's promise "read only" — the token could write and delete.
    workflow = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                            ".github", "workflows", "r2-inventory.yml")
    with open(workflow, encoding="utf-8") as handle:
        code = "\n".join(line.rstrip("\n").split("#", 1)[0] for line in handle).replace("\\\n", " ")
    for verb in (" rm ", " mv ", " sync ", "delete-object", "put-object", "abort-multipart",
                 "put-bucket", "delete-bucket", "complete-multipart"):
        assert verb not in code, f"r2-inventory.yml must only read, found `{verb.strip()}`"
    for line in code.splitlines():
        if " s3 cp " in line:
            # Source first: from the bucket into build/, never back.
            assert re.search(r' s3 cp [^"]*"s3://[^"]*" +"build/', line), \
                f"s3 cp only from the bucket: {line.strip()}"
    print("r2_inventory self-test: ok")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    rep = sub.add_parser("report", help="listing + manifests -> markdown on stdout")
    rep.add_argument("--listing", required=True)
    rep.add_argument("--uploads")
    rep.add_argument("--manifests", required=True, help="directory with the downloaded manifests")
    rep.add_argument("--prefix", default=PREFIX)
    rep.add_argument("--bucket", default="buddy-tiles")
    rep.add_argument("--json", help="also write the analysis as JSON")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.command != "report":
        parser.print_help()
        return 2
    manifests = {f["manifest"]: read_json(os.path.join(args.manifests, f["manifest"]))
                 for f in FAMILIES}
    result = analyse(load_objects(read_json(args.listing)),
                     load_uploads(read_json(args.uploads)), manifests, args.prefix)
    sys.stdout.write(render(result, args.bucket))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
    for e in result["errors"]:
        print(f"::error::{e}", file=sys.stderr)
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
