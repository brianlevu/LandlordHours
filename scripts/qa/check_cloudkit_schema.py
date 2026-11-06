#!/usr/bin/env python3
"""Pre-release gate: does the CloudKit Production schema hold every record type and field this
build writes? (diagnosis 2026-10-25 §7.4: 1.x pushes were rejected for months because the
CustomCategory type was missing in Production.)

The expected side is scripts/qa/cloudkit_schema_expected.json, which a unit test
(CloudKitSchemaManifestTests) keeps equal to what the code writes. The actual side is a schema
export from the console's CLI:

  xcrun cktool save-token --type management          # once, Brian's sign-in in the browser
  xcrun cktool export-schema --team-id G68NLC3DA3 --container-id iCloud.com.openclaw.landlordhours \\
      --environment production --output-file /tmp/landlordhours-production.ckdb
  scripts/qa/check_cloudkit_schema.py /tmp/landlordhours-production.ckdb

It also checks the indexes package K relies on: `appUserId` QUERYABLE on every type (the Console
and `cktool` reads), and reports whether `___recordID` is QUERYABLE (needed only to list records
in the Console, §3.5). Exit 0 = PASS, 1 = something this build writes is missing.
"""
import json
import os
import re
import sys

TYPE_MAP = {"STRING": "STRING", "TIMESTAMP": "TIMESTAMP", "INT64": "INT64", "DOUBLE": "DOUBLE", "LIST<STRING>": "LIST<STRING>"}


def parse_ckdb(text):
    """{type: {field: (TYPE, set(flags))}} from a .ckdb export."""
    types = {}
    for match in re.finditer(r"RECORD TYPE\s+(\w+)\s*\((.*?)\);", text, re.S):
        name, body = match.group(1), match.group(2)
        fields = {}
        for raw in body.split(","):
            line = raw.strip()
            if not line or line.startswith("GRANT"):
                continue
            parts = line.replace('"', "").split()
            if len(parts) < 2:
                continue
            field, kind = parts[0], parts[1]
            flags = {p.upper() for p in parts[2:]}
            fields[field] = (kind.upper(), flags)
        types[name] = fields
    return types


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    expected = json.load(open(os.path.join(here, "cloudkit_schema_expected.json")))
    actual = parse_ckdb(open(sys.argv[1]).read())
    problems, notes = [], []
    for rtype, fields in sorted(expected.items()):
        if rtype not in actual:
            problems.append(f"record type {rtype} is missing in Production (every push of it fails)")
            continue
        for field, kind in sorted(fields.items()):
            got = actual[rtype].get(field)
            if got is None:
                problems.append(f"{rtype}.{field} ({kind}) is missing in Production")
            elif TYPE_MAP.get(kind) != got[0]:
                problems.append(f"{rtype}.{field} is {got[0]} in Production, the code writes {kind}")
        app_user = actual[rtype].get("appUserId")
        if app_user and "QUERYABLE" not in app_user[1]:
            problems.append(f"{rtype}.appUserId is not QUERYABLE")
        record_id = actual[rtype].get("___recordID")
        if not record_id or "QUERYABLE" not in record_id[1]:
            notes.append(f"{rtype}: recordName (___recordID) is not QUERYABLE (Console can't list it; the app doesn't need it)")
    for note in notes:
        print("note:", note)
    for problem in problems:
        print("FAIL:", problem)
    if problems:
        print(f"FAIL: {len(problems)} problem(s). Add them in Development, then Deploy Schema Changes to Production.")
        return 1
    print(f"PASS: Production holds all {sum(len(f) for f in expected.values())} fields of {len(expected)} record types this build writes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
