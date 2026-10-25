#!/usr/bin/env python3
"""Write Sources/Resources/Strings/Identity.xcstrings from what the compiler extracted.

Package K's strings all use `String(localized: "...", table: "Identity")`. After a build, every
`*.stringsdata` file in the target's intermediates lists the keys per table; this script collects
the `Identity` table, keeps any existing translations in the catalog, adds new keys (empty
entries, like the other catalogs) and drops keys no source uses any more.

Usage: build_identity_catalog.py <DerivedData path> [<repo root>]
"""
import glob
import json
import os
import sys

dd = sys.argv[1]
repo = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
paths = glob.glob(os.path.join(dd, "Build/Intermediates.noindex/LandlordHours.build/*/LandlordHours.build/Objects-normal/*/*.stringsdata"))
keys = {}
for path in paths:
    data = json.load(open(path))
    for item in data.get("tables", {}).get("Identity", []):
        keys.setdefault(item["key"], item.get("comment", ""))
catalog_path = os.path.join(repo, "Sources/Resources/Strings/Identity.xcstrings")
existing = json.load(open(catalog_path)) if os.path.exists(catalog_path) else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
strings = {}
for key in sorted(keys):
    entry = existing["strings"].get(key, {})
    if keys[key]:
        entry["comment"] = keys[key]
    # Positional specifiers for strings with more than one argument (Xcode does the same).
    if key.count("%") > 1 and "localizations" not in entry:
        n = 0
        out = ""
        i = 0
        while i < len(key):
            if key[i] == "%" and i + 1 < len(key) and key[i + 1] != "%":
                n += 1
                out += f"%{n}$"
                i += 1
                continue
            out += key[i]
            i += 1
        entry["localizations"] = {"en": {"stringUnit": {"state": "new", "value": out}}}
    strings[key] = entry
catalog = {"sourceLanguage": "en", "strings": strings, "version": existing.get("version", "1.0")}
with open(catalog_path, "w") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False, sort_keys=False)
    f.write("\n")
print(f"Identity.xcstrings: {len(strings)} keys from {len(paths)} stringsdata files")
