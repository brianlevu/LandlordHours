#!/usr/bin/env python3
"""Builds / checks Sources/Resources/Strings/Inbox.xcstrings from the Inbox package's Swift.

Every `String(localized: "key", defaultValue: "…", table: "Inbox")` in Sources/Views/Inbox/*.swift is
a key. Interpolations need a format specifier in the catalog (Swift emits %lld for Int, %@ for
String); SPEC maps the keys that interpolate. `--write` rewrites the catalog, the default checks it.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parents[2]
src = root / "Sources/Views/Inbox"
catalog = root / "Sources/Resources/Strings/Inbox.xcstrings"

SPEC = {
    "inbox.row.title": "%@ at %@",
    "inbox.toast.logged": "Logged %@",
    "inbox.toast.loggedMany": "Logged %lld",
    "inbox.row.confirmHours": "Confirm %@",
    "inbox.batch.confirm": "Confirm %lld likely",
    "inbox.backfill.title": "%lld from your last 90 days",
    "backfill.events.progress": "%lld of %lld events",
    "backfill.found.line": "%lld found so far",
    "backfill.scanning.a11y": "Looking through your calendar. %@",
    "confirm.mute.named": "Events named “%@”",
    "confirm.subtitle": "%@ · %@",
    "confirm.schedule": "Your calendar had this from %@ to %@. Change it if the work ran long or short.",
    "confirm.log.hours": "Log %@",
    "confirm.missing": "Add %@ to log this.",
}

pat = re.compile(r'String\(localized:\s*"([^"]+)",\s*defaultValue:\s*"((?:[^"\\]|\\.|\\\([^)]*\))*)",\s*table:\s*"Inbox"(?:,\s*comment:\s*"((?:[^"\\]|\\.)*)")?')
found = {}
for f in sorted(src.glob("*.swift")):
    for m in pat.finditer(f.read_text()):
        key, default, comment = m.group(1), m.group(2), m.group(3)
        default = default.replace('\\u{201C}', '“').replace('\\u{201D}', '”')
        if "\\(" in default:
            if key not in SPEC:
                sys.exit(f"{f.name}: {key} interpolates but has no SPEC entry")
            n = default.count("\\(")
            if SPEC[key].count("%") != n:
                sys.exit(f"{key}: {n} interpolations vs {SPEC[key]}")
            value = SPEC[key]
        else:
            value = default
        if key in found and found[key][0] != value:
            sys.exit(f"{key}: two different values {found[key][0]!r} / {value!r}")
        found[key] = (value, comment)

def entry(value, comment):
    e = {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": value}}}}
    if comment:
        e["comment"] = comment
    return e

want = {"sourceLanguage": "en", "strings": {k: entry(*found[k]) for k in sorted(found)}, "version": "1.0"}
if "--write" in sys.argv:
    catalog.write_text(json.dumps(want, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {len(found)} keys")
else:
    have = json.loads(catalog.read_text()) if catalog.exists() else {"strings": {}}
    missing = sorted(set(found) - set(have["strings"]))
    extra = sorted(set(have["strings"]) - set(found))
    wrong = [k for k in found if k in have["strings"] and have["strings"][k]["localizations"]["en"]["stringUnit"]["value"] != found[k][0]]
    print(f"{len(found)} keys; missing {missing}; extra {extra}; wrong {wrong}")
    sys.exit(1 if (missing or extra or wrong) else 0)
