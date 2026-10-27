#!/usr/bin/env python3
"""Turn the raw captures from capture_upgrade_fixture.sh into package K's named fixtures.

The shipped builds' DEBUG seeds file their records under `debug-<scenario>` profile ids, which
2.2 ignores on purpose (D11). This script renames those ids to the id kinds real users carry and
removes the mock's default contact email. Record bytes (the JSON blobs) are never edited.

Usage: rekey_fixture.py <capture-out-dir>   (reads <out>/raw/*, writes <out>/upgrade/<state>.plist|.md)
"""
import json
import plistlib
import shutil
import sys
from pathlib import Path

EMAIL_A = "email-upgrade.tester@example.com"
EMAIL_B = "email-old.profile@example.com"
LOCAL_A = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"
LOCAL_B = "local-6F1E2D3C-0000-4000-8000-0000000C0B02"
LOCAL_S = "local-6F1E2D3C-0000-4000-8000-0000000C0533"
APPLE = "001234.k7f1xture0a00000000000000000000.0101"

AUTH_KEYS = ["appleUserId", "appleUserName", "appleUserEmail", "emailUserId", "emailUserName",
             "emailUserEmail", "localProfileId", "localProfileName", "localProfileEmail", "loginType"]


def load(raw: Path, name: str) -> dict:
    with open(raw / name / "defaults.plist", "rb") as f:
        return plistlib.load(f)


def rename(d: dict, mapping: dict) -> dict:
    out = {}
    for key, value in d.items():
        new_key = key
        for old, new in mapping.items():
            prefix = f"u.{old}."
            if key.startswith(prefix):
                new_key = f"u.{new}." + key[len(prefix):]
        if isinstance(value, str) and value in mapping:
            value = mapping[value]
        out[new_key] = value
    return out


def counts(d: dict) -> dict:
    result = {}
    for key, value in d.items():
        for suffix, label in ((".LandlordHours.entries", "entries"), (".LandlordHours.properties", "properties")):
            if key.endswith(suffix) and isinstance(value, (bytes, bytearray)):
                owner = key[2:-len(suffix)] if key.startswith("u.") else "(unscoped)"
                result.setdefault(owner, {})[label] = len(json.loads(value.decode("utf-8")))
        if key in ("LandlordHours.entries", "LandlordHours.properties") and isinstance(value, (bytes, bytearray)):
            result.setdefault("(unscoped)", {})[key.split(".")[-1]] = len(json.loads(value.decode("utf-8")))
    return result


def write(out: Path, state: str, d: dict, readme: str, files_from: Path = None, folder_map: dict = None):
    # Flat, unique file names: the test target bundles every file under Tests/ as a resource, and
    # two files with one name would collide. `<state>.plist` is the defaults domain, `<state>.md`
    # its README, `<state>.<folder>.suggestions.json` a capture inbox file.
    target = out / "upgrade"
    target.mkdir(parents=True, exist_ok=True)
    with open(target / f"{state}.plist", "wb") as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_XML, sort_keys=True)
    extra = []
    if files_from is not None and (files_from / "ApplicationSupport" / "Capture").exists():
        for folder in sorted((files_from / "ApplicationSupport" / "Capture").iterdir()):
            src = folder / "suggestions.json"
            if not src.exists():
                continue
            name = (folder_map or {}).get(folder.name, folder.name)
            dest = target / f"{state}.{name}.suggestions.json"
            shutil.copyfile(src, dest)
            extra.append(dest.name)
    c = counts(d)
    with open(target / f"{state}.md", "w") as f:
        f.write(readme.strip() + "\n\nExpected counts (decoded from the captured blobs):\n\n")
        for owner in sorted(c):
            f.write(f"- `{owner}`: {c[owner].get('entries', 0)} entries, {c[owner].get('properties', 0)} properties\n")
        for name in extra:
            f.write(f"\nCapture inbox file: `{name}`\n")
        f.write("\nCaptured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.\n"
                "Do not edit by hand; re-run the capture instead.\n")
    print(f"wrote {state}: {c}")


def main():
    out = Path(sys.argv[1])
    raw = out / "raw"
    fixture_email = EMAIL_A[len("email-"):]

    # D2: 1.0.6 signed in with an email "account".
    d = rename(load(raw, "106-one-email"), {"debug-frequent": EMAIL_A})
    d["emailUserEmail"] = fixture_email
    write(out, "D2-106-signed-in", d, """
# D2 · 1.0.6 signed in (email account)

Build: LandlordHours 1.0.6 (`9c6a25e`, build 202608260402), Debug, simulator iOS 27.0.
Seed: `-LHMockScenario frequent` (1.0.6's own seed), re-keyed `debug-frequent` → `email-upgrade.tester@example.com`.
Expect: one group, Pro on, spouse tracking on, onboarding complete, no Welcome after 2.2.
""")

    # D3: 1.0.6 signed out, two email profiles left on the device.
    d = rename(load(raw, "106-two-email"), {"debug-frequent": EMAIL_A, "debug-occasional": EMAIL_B})
    for key in AUTH_KEYS:
        d.pop(key, None)
    write(out, "D3-106-signed-out-two", d, """
# D3 · 1.0.6 signed out, two email profiles on the device

Build: 1.0.6 (`9c6a25e`). Seed: `-LHMockScenario occasional`, then `-LHMockScenario frequent`;
re-keyed to two email ids; the sign-in keys removed (what 1.0.6 sign-out leaves).
Expect: two non-empty groups; the larger is primary; the two-sets question for the other.
""")

    # D9: pre-UserScope unscoped keys (1.0.x before per-user scoping): the same 1.0.6 records with
    # the `u.<id>.` prefix stripped and no sign-in keys.
    src = load(raw, "106-one-email")
    d = {}
    for key, value in src.items():
        if key in AUTH_KEYS:
            continue
        if key.startswith("u.debug-frequent."):
            d[key[len("u.debug-frequent."):]] = value
        elif not key.startswith("u."):
            d[key] = value
    write(out, "D9-unscoped", d, """
# D9 · unscoped 1.0.x keys (never signed in after per-user scoping)

Build: 1.0.6 (`9c6a25e`) records, `u.debug-frequent.` prefix stripped (the pre-scoping key names
are the same base names, see `AppViewModel.unscopedLegacyKeys`). Pair with zone case `Z4-ownerless`.
Expect: one `legacy-unscoped` group.
""")

    # D4: 2.0.1 ran its own email → local migration.
    d = load(raw, "201-email-migrated")
    write(out, "D4-201-email-migrated", d, """
# D4 · 2.0.1 upgrader: email id kept as the local profile id

Build: LandlordHours 2.0.1 lineage (`188cacd`), Debug. Seed: `-LHSeedLegacyEmailProfile` (2.0.1's
own 1.0.6-shaped seed), after which 2.0.1's `ProfileMigration` moved `emailUserId` to `localProfileId`.
Expect: active group `email-upgrade.tester@example.com` plus a signed-out `email-old.profile@example.com`.
""")

    # D5: 2.0.1 "Get started" local profile.
    d = rename(load(raw, "201-one-local"), {"debug-occasional": LOCAL_A})
    d.pop("localProfileEmail", None)
    write(out, "D5-201-local", d, """
# D5 · 2.0.1 local profile ("Get started")

Build: 2.0.1 (`188cacd`). Seed: `-LHMockScenario occasional`, re-keyed to a `local-<UUID>` id; the
mock's contact email removed (2.0 local profiles carry none).
""")

    # D6 / D7: 2.0.1 Sign in with Apple (+ a half-made empty local profile for D7).
    src = rename(load(raw, "201-apple-plus-empty-local"), {"debug-frequent": APPLE})
    src["appleUserId"] = src.pop("localProfileId", APPLE)
    if "localProfileName" in src:
        src["appleUserName"] = src.pop("localProfileName")
    src.pop("localProfileEmail", None)
    src["loginType"] = "apple"
    write(out, "D7-201-apple-plus-empty-local", src, """
# D7 · 2.0.1 Apple sign-in plus the empty "Get started" profile (Brian's 2.0 shape)

Build: 2.0.1 (`188cacd`). Seed: `-LHSeedWelcomeState deadEnd` (empty `local-welcome-fixture`), then
`-LHMockScenario frequent`, re-keyed to an Apple id under `appleUserId`.
Expect: one non-empty group (the Apple id); the empty local group dropped silently.
""")
    d6 = {k: v for k, v in src.items() if not k.startswith("u.local-welcome-fixture.")}
    write(out, "D6-201-apple", d6, """
# D6 · 2.0.1 Sign in with Apple

Same capture as D7 with the empty local profile's keys left out.
""")

    # D8: two 2.0.1 local profiles with data (switch profile).
    d = rename(load(raw, "201-two-local"), {"debug-occasional": LOCAL_A, "debug-frequent": LOCAL_B})
    d.pop("localProfileEmail", None)
    d["previousProfileId"] = LOCAL_A
    write(out, "D8-201-two-local", d, """
# D8 · 2.0.1 two local profiles with records (Switch profile)

Build: 2.0.1 (`188cacd`). Seed: `-LHMockScenario occasional`, then `-LHMockScenario frequent`;
re-keyed to two `local-<UUID>` ids; `previousProfileId` names the first.
Expect: two non-empty groups; the two-sets question.
""")

    # Suggestions file (U33).
    d = rename(load(raw, "201-suggestions"), {"debug-emptyMainTabs": LOCAL_S})
    d.pop("localProfileEmail", None)
    write(out, "S-201-suggestions", d, """
# 2.0.1 capture inbox file

Build: 2.0.1 (`188cacd`). Seed: `-LHMockScenario emptyMainTabs -LHSeedSuggestions inbox -LHFixedNow 2026-10-16T15:00`;
`Capture/<id>/suggestions.json` re-keyed (folder name) to a `local-<UUID>` id.
""", files_from=raw / "201-suggestions", folder_map={"debug-emptyMainTabs": LOCAL_S})

    # D11: DEBUG ids exactly as written (never offered, never migrated).
    d = load(raw, "201-one-local")
    d["localProfileEmail"] = fixture_email
    write(out, "D11-debug", d, """
# D11 · DEBUG mock profile ids (`debug-*`)

Build: 2.0.1 (`188cacd`), `-LHMockScenario occasional`, not re-keyed. Expect: ignored by the inventory.
""")


if __name__ == "__main__":
    main()
