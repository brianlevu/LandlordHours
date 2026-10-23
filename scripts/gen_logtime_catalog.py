#!/usr/bin/env python3
"""Regenerates Sources/Resources/Localizable.xcstrings for the Log time sheet.

Scans the Log time files for String(localized:), Text/Button/Label/TextField literals and
accessibility strings. Interpolations become %@ (Int counts become %lld). Run from the repo root.
"""
import json, re, glob, sys

FILES = glob.glob("Sources/Views/LogTime/*.swift") + [
    "Sources/Services/NoteReading/NoteReaderChain.swift",
]
PATTERNS = [
    r'String\(localized:\s*"', r'\bText\(\s*"', r'\bButton\(\s*"', r'\bLabel\(\s*"', r'\bTextField\(\s*"',
    r'\.accessibilityLabel\(\s*"', r'\.accessibilityHint\(\s*"',
]
INT_EXPR = {"count", "attachments.count"}
ESC = {r'\u{201C}': "“", r'\u{201D}': "”", r'\u{2019}': "’", r'\u{2026}': "…",
       r'\u{00B7}': "·", r'\u{00A0}': " ", r'\"': '"', r'\n': "\n"}
SKIP = {"", "log.sheet"}

def unescape(s):
    for k, v in ESC.items(): s = s.replace(k, v)
    return s

keys = {}
for path in FILES:
    src = open(path).read()
    for pat in PATTERNS:
        for m in re.finditer(pat, src):
            i = m.end(); out = ""; depth = 0; expr = ""
            while i < len(src):
                c = src[i]
                if depth == 0 and c == '"': break
                if depth == 0 and src[i:i+2] == "\\(":
                    depth = 1; i += 2; expr = ""; continue
                if depth > 0:
                    if c == "(": depth += 1
                    elif c == ")":
                        depth -= 1
                        if depth == 0: out += "%lld" if expr.strip() in INT_EXPR else "%@"
                    if depth > 0: expr += c
                    i += 1; continue
                if c == "\\" and src[i+1] == '"': out += '\\"'; i += 2; continue
                if c == "\\" and src[i+1] == "u":
                    j = src.index("}", i); out += src[i:j+1]; i = j + 1; continue
                out += c; i += 1
            out = unescape(out)
            if out in SKIP or out.startswith(("log.", "timer.", "picker.", "shell.")): continue
            keys[out] = None

# Strings from files outside the Log time folder (Settings > Auto-capture).
for extra in ["Read my notes with Apple\u2019s model",
              "Fills Log time from what you write or say. Off, it still matches your own words, like a rental name or \u201C2 hours\u201D."]:
    keys[extra] = None

# Plural variations for counted strings.
def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
catalog = {}
for k in sorted(keys):
    entry = {"extractionState": "manual", "localizations": {"en": unit(k)}}
    if k == "%lld photos added":
        entry["localizations"]["en"] = {"variations": {"plural": {"one": unit("%lld photo added"), "other": unit("%lld photos added")}}}
    if k == "Your note mentions %lld rentals. Log each one on its own.":
        entry["localizations"]["en"] = {"variations": {"plural": {"one": unit("Your note mentions %lld rental. Log it on its own."), "other": unit(k)}}}
    catalog[k] = entry
json.dump({"sourceLanguage": "en", "strings": catalog, "version": "1.0"},
          open("Sources/Resources/Localizable.xcstrings", "w"), indent=2, ensure_ascii=False)
print(len(catalog), "strings", file=sys.stderr)
