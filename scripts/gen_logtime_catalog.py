#!/usr/bin/env python3
"""Regenerates Sources/Resources/Strings/LogTime.xcstrings (package E's catalog).

Scans Sources/Views/LogTime/*.swift for `lt("...")` (the package's one string helper, which reads
the LogTime table with the English text as the key). Interpolations become %@ (Strings) or %lld
(the names in INT_EXPR). Run from the repo root:

    python3 scripts/gen_logtime_catalog.py            # rewrite the catalog
    python3 scripts/gen_logtime_catalog.py --check    # exit 1 if the catalog is stale

Strings used by other packages' files for Log time's features (the Settings switch "Read my notes
with Apple's model") live in those packages' own catalogs.
"""
import glob
import json
import re
import sys

FILES = sorted(glob.glob("Sources/Views/LogTime/*.swift"))
OUT = "Sources/Resources/Strings/LogTime.xcstrings"
START = re.compile(r'\blt\(\s*"')
INT_EXPR = {"count", "attachments.count", "moreCount"}
SKIP = {""}


def unescape(s):
    s = re.sub(r'\\u\{([0-9A-Fa-f]+)\}', lambda m: chr(int(m.group(1), 16)), s)
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def scan(src):
    for m in START.finditer(src):
        i = m.end()
        out = ""
        depth = 0
        expr = ""
        while i < len(src):
            c = src[i]
            if depth == 0 and c == '"':
                break
            if depth == 0 and src[i:i + 2] == "\\(":
                depth = 1
                i += 2
                expr = ""
                continue
            if depth > 0:
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        out += "%lld" if expr.strip() in INT_EXPR else "%@"
                if depth > 0:
                    expr += c
                i += 1
                continue
            if c == "\\" and src[i + 1] == '"':
                out += '\\"'
                i += 2
                continue
            if c == "\\" and src[i + 1] == "u":
                j = src.index("}", i)
                out += src[i:j + 1]
                i = j + 1
                continue
            out += c
            i += 1
        yield unescape(out)


def build():
    keys = set()
    for path in FILES:
        for key in scan(open(path).read()):
            if key not in SKIP:
                keys.add(key)

    def unit(v):
        return {"stringUnit": {"state": "translated", "value": v}}

    catalog = {k: {"extractionState": "manual", "localizations": {"en": unit(k)}} for k in sorted(keys)}
    return {"sourceLanguage": "en", "strings": catalog, "version": "1.0"}


if __name__ == "__main__":
    data = build()
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        try:
            same = open(OUT).read() == text
        except FileNotFoundError:
            same = False
        sys.exit(0 if same else 1)
    open(OUT, "w").write(text)
    print(len(data["strings"]), "strings", file=sys.stderr)
