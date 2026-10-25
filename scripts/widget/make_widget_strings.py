#!/usr/bin/env python3
"""Regenerate Sources/Widget/Widgets.xcstrings from the `table: "Widgets"` calls in the widget code.

Every user-facing widget string is `String(localized: "key", defaultValue: "...\\(x)...", table: "Widgets")`
(or a `LocalizedStringResource` with the same shape). This reads those calls and writes the English
catalog, so the code stays the source of truth for the words and the catalog never drifts.
Interpolations become %lld for the names in INTS (or anything ending in `Count`) and %@ otherwise.
Keys in PLURALS get an English one/other variation. Translators add languages in Xcode.

Usage (repo root): python3 scripts/widget/make_widget_strings.py
"""
import json, re

FILES = ["Sources/Shared/WidgetSurface.swift", "Sources/Widget/WidgetSurfaceViews.swift",
         "Sources/Widget/LandlordHoursWidget.swift", "Sources/Widget/WidgetConfirmIntent.swift"]
INTS = {"gap", "goalNumber", "rentalCount", "behind", "pendingCount"}
PLURALS = {"widget.pace.behind": ("Behind by %lld hour", "Behind by %lld hours")}
OUT = "Sources/Widget/Widgets.xcstrings"

found = {}
for f in FILES:
    s = open(f).read()
    for m in re.finditer(r'(?:String\(localized:|LocalizedStringResource\()\s*"([^"]+)",\s*defaultValue:\s*"((?:[^"\\]|\\.)*)",\s*table:\s*"Widgets"', s):
        key, value = m.group(1), m.group(2)

        def sub(mm):
            e = mm.group(1)
            return "%lld" if e in INTS or e.split(".")[-1] in INTS else "%@"

        value = re.sub(r"\\\((.*?)\)", sub, value).replace('\\"', '"')
        assert found.get(key, value) == value, f"{key} has two different default values"
        found[key] = value

strings = {}
for key, value in sorted(found.items()):
    loc = {"stringUnit": {"state": "translated", "value": value}}
    if key in PLURALS:
        one, other = PLURALS[key]
        loc = {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": one}},
                                         "other": {"stringUnit": {"state": "translated", "value": other}}}}}
    strings[key] = {"extractionState": "manual", "localizations": {"en": loc}}
json.dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, open(OUT, "w"), indent=2, ensure_ascii=False)
open(OUT, "a").write("\n")
print(f"{len(strings)} strings -> {OUT}")
