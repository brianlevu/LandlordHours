#!/usr/bin/env python3
"""Regenerates Sources/Resources/LogTimeProto.xcstrings from pl("...") and PT("...") calls in the prototype."""
import json, re, glob
keys = {}
for path in glob.glob("Sources/Views/LogTime/Proto/*.swift"):
    s = open(path).read()
    for m in re.finditer(r'\b(?:pl|PT)\("', s):
        i = m.end(); out = ""; depth = 0
        while i < len(s):
            c = s[i]
            if depth == 0 and c == '"': break
            if depth == 0 and s[i:i+2] == "\\(":
                depth = 1; i += 2; out += "%@"; continue
            if depth > 0:
                if c == "(": depth += 1
                elif c == ")": depth -= 1
                i += 1; continue
            out += c; i += 1
        keys[out] = {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": out}}}}
cat = {"sourceLanguage": "en", "strings": dict(sorted(keys.items())), "version": "1.0"}
json.dump(cat, open("Sources/Resources/LogTimeProto.xcstrings", "w"), indent=2, ensure_ascii=False)
print(len(keys), "strings")
