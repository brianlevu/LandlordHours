#!/usr/bin/env python3
"""Builds Sources/Resources/Home/Home.xcstrings (the String Catalog for table "Home") from the
.stringsdata files the Swift compiler writes during a build. Keys keep their format specifiers
(%lld, %@), so interpolated strings are catalogued exactly as Xcode would.

    python3 scripts/l10n/home_catalog.py DERIVED_DATA_DIR [--check]

Existing entries (and any translations added to them) are kept; new keys are added with the key as
the English value; keys no longer used are marked stale, never deleted. --check exits 1 if the
catalog would change (for a release gate)."""
import json, os, sys

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if not args:
        sys.exit(__doc__)
    keys = {}
    for root, _, files in os.walk(args[0]):
        for f in files:
            if not f.endswith(".stringsdata"):
                continue
            try:
                d = json.load(open(os.path.join(root, f)))
            except Exception:
                continue
            for entry in d.get("tables", {}).get("Home", []):
                keys.setdefault(entry["key"], os.path.basename(d.get("source", "")))
    out = os.path.join(os.path.dirname(__file__), "..", "..", "Sources", "Resources", "Home", "Home.xcstrings")
    out = os.path.normpath(out)
    cat = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    if os.path.exists(out):
        cat = json.load(open(out))
    strings = cat["strings"]
    for k in keys:
        if k not in strings:
            strings[k] = {"extractionState": "manual",
                          "localizations": {"en": {"stringUnit": {"state": "translated", "value": k}}}}
        elif strings[k].get("extractionState") == "stale":
            strings[k]["extractionState"] = "manual"
    for k, v in strings.items():
        if k not in keys and v.get("extractionState") != "stale":
            v["extractionState"] = "stale"
    text = json.dumps(cat, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    old = open(out).read() if os.path.exists(out) else ""
    if check:
        sys.exit(0 if old == text else 1)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(text)
    print(f"{len(keys)} keys from the build, {len(strings)} in {out}")

main()
