#!/usr/bin/env python3
"""Recompute package K's "never lose a record" invariant (§2.3) from a pulled app container.

Independent of the app's own ledger: it re-derives every record version from the raw files and
checks that each one has a place.

  every distinct (UUID, content) version present at S1 (the S2 backup: every u.* and unscoped
  blob) or at S5 (migration/cloud-snapshot.json) is, now, in exactly one of: the live set
  (v2.* blobs), an archive group (archive/*.json), Recently removed (archive/recently-removed.json),
  or the backup / snapshot as a last-writer-wins loser whose UUID is placed; a tombstoned UUID
  needs a copy in Recently removed or the backup.

Usage:
  identity_invariant.py <container-dir>
    <container-dir> is what `xcrun devicectl device copy from --domain-type appDataContainer`
    (or `simctl get_app_container … data`) produced: it holds Library/Preferences and
    Library/Application Support.
Exit 0 = PASS, 1 = FAIL, 2 = the container has no migration files.
"""
import base64
import datetime
import glob
import json
import os
import plistlib
import sys

BUNDLE = "com.openclaw.landlordhours"
REF = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc).timestamp()


def ms(ref_seconds):
    """Foundation's default Date coding is seconds since 2001; compare at CloudKit's millisecond."""
    if ref_seconds is None:
        return None
    return int(round((ref_seconds + REF) * 1000))


def entry_key(e):
    """A device TimeEntry (JSON coding keys) as a canonical content tuple."""
    return ("TimeEntry", e.get("propertyId", "").upper(), e.get("participant"), e.get("category"), float(e.get("hours", 0)),
            ms(e.get("date")), e.get("notes", ""), ms(e.get("createdAt")), ms(e.get("modifiedAt", e.get("createdAt"))),
            e.get("importSource"), e.get("importExternalId"), e.get("importCalendarId"), ms(e.get("detectedAt")),
            ms(e.get("confirmedAt")), e.get("sourceDetail"), e.get("sourceKey"), e.get("recordDescription"))


def prop_key(p):
    aliases = sorted(a.strip() for a in p.get("aliases", []) if a.strip())
    return ("Property", p.get("name"), p.get("address"), p.get("propertyType"), ms(p.get("createdAt")),
            ms(p.get("modifiedAt", p.get("createdAt"))), tuple(aliases), bool(p.get("isOwnerOccupied", False)))


def zone_value(v):
    if v is None:
        return None
    # Swift encodes `.date(Date)` as {"date": {"_0": <seconds since 2001>}}.
    (kind, value), = v.items()
    if isinstance(value, dict) and "_0" in value:
        value = value["_0"]
    return value


def zone_key(r):
    """A ZoneRecord from cloud-snapshot.json as the same canonical tuple."""
    f = {k: zone_value(v) for k, v in r.get("fields", {}).items()}
    if r["recordType"] == "TimeEntry":
        return ("TimeEntry", (f.get("propertyId") or "").upper(), f.get("participant"), f.get("category"), float(f.get("hours") or 0),
                ms(f.get("date")), f.get("notes") or "", ms(f.get("createdAt")), ms(f.get("modifiedAt")),
                f.get("importSource"), f.get("importExternalId"), f.get("importCalendarId"), ms(f.get("detectedAt")),
                ms(f.get("confirmedAt")), f.get("sourceDetail"), f.get("sourceKey"), f.get("recordDescription"))
    if r["recordType"] == "Property":
        aliases = f.get("aliases") or []
        if f.get("aliasCount") == 0:
            aliases = []
        return ("Property", f.get("name"), f.get("address"), f.get("propertyType"), ms(f.get("createdAt")), ms(f.get("modifiedAt")),
                tuple(sorted(a.strip() for a in aliases if a.strip())), bool(f.get("isOwnerOccupied") or 0))
    return None


def versions_from_blob(blob, kind):
    try:
        items = json.loads(blob.decode("utf-8") if isinstance(blob, (bytes, bytearray)) else blob)
    except Exception:
        return set(), True
    out = set()
    for item in items:
        key = entry_key(item) if kind == "entries" else prop_key(item)
        out.add((item["id"].upper(), key))
    return out, False


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    prefs_path = os.path.join(root, "Library", "Preferences", f"{BUNDLE}.plist")
    app_support = os.path.join(root, "Library", "Application Support")
    migration = os.path.join(app_support, "migration")
    if not os.path.isdir(migration):
        print("NO MIGRATION FILES: the container never ran 2.2's device merge")
        return 2
    prefs = plistlib.load(open(prefs_path, "rb")) if os.path.exists(prefs_path) else {}

    # S1: every blob in the oldest backup.
    backups = sorted(glob.glob(os.path.join(migration, "v2-backup-*.json")))
    before = set()
    unreadable = 0
    if backups:
        backup = json.load(open(backups[0]))
        for key, encoded in backup.get("keys", {}).items():
            for suffix, kind in ((".LandlordHours.entries", "entries"), (".LandlordHours.properties", "properties")):
                is_unscoped = key == suffix[1:]
                if (key.startswith("u.") and key.endswith(suffix) and not key.startswith("u.debug-")) or is_unscoped:
                    value = plistlib.loads(base64.b64decode(encoded))["v"]
                    found, bad = versions_from_blob(value, kind)
                    before |= found
                    unreadable += bad
    # S5: the zone snapshot (user records only; debug owners are not ours).
    snapshot_path = os.path.join(migration, "cloud-snapshot.json")
    zone_versions = set()
    unparsed = set()
    if os.path.exists(snapshot_path):
        snap = json.load(open(snapshot_path))
        for r in snap.get("records", []):
            owner = zone_value(r.get("fields", {}).get("appUserId"))
            if owner and owner.startswith("debug-"):
                continue
            k = zone_key(r)
            if k is None:
                continue
            zone_versions.add((r["recordName"].upper(), k))
    before |= zone_versions

    # Now: live, archived, removed.
    live = set()
    for key, kind in (("v2.LandlordHours.entries", "entries"), ("v2.LandlordHours.properties", "properties")):
        if key in prefs:
            found, _ = versions_from_blob(prefs[key], kind)
            live |= found
    archived, removed = set(), set()
    archive_dir = os.path.join(app_support, "archive")
    for path in glob.glob(os.path.join(archive_dir, "*.json")):
        name = os.path.basename(path)
        data = json.load(open(path))
        if name == "recently-removed.json":
            for item in data:
                if item.get("entry"):
                    removed.add((item["entry"]["id"].upper(), entry_key(item["entry"])))
                if item.get("property"):
                    removed.add((item["property"]["id"].upper(), prop_key(item["property"])))
        elif name != "bulk-hold.json":
            for e in data.get("entries", []):
                archived.add((e["id"].upper(), entry_key(e)))
            for p in data.get("properties", []):
                archived.add((p["id"].upper(), prop_key(p)))
            for r in data.get("unparsedRecords", []):
                unparsed.add(r["recordName"].upper())
    tombstoned = set()
    sync_dir = os.path.join(app_support, "Sync")
    for path in glob.glob(os.path.join(sync_dir, "*", "pushed-fingerprints.json")):
        tombstoned |= {n.upper() for n in json.load(open(path)).get("pendingDeletes") or []}
    deleted_names = {n.upper() for n in (prefs.get("v2.deletedRecordNames") or {}).keys()}

    placed = live | archived | removed
    placed_ids = {v[0] for v in placed}
    failures = []
    losers = 0
    for version in sorted(before):
        if version in placed:
            continue
        uuid = version[0]
        if uuid in unparsed:
            continue
        if uuid in placed_ids:
            losers += 1          # an older version: kept in the backup or the snapshot
            continue
        if uuid in tombstoned or uuid in deleted_names:
            if uuid in {v[0] for v in removed}:
                continue
            losers += 1          # a delete the person made; the copy is in the backup
            continue
        failures.append(uuid)
    both = (live & archived) | (live & removed)
    print(f"S1+S5 versions: {len(before)} (device+zone), live {len(live)}, archived {len(archived)}, "
          f"removed {len(removed)}, older versions in backup/snapshot {losers}, unparsed kept {len(unparsed)}, "
          f"unreadable blobs {unreadable}")
    if both:
        print(f"FAIL: {len(both)} version(s) both live and archived/removed")
    if failures:
        print(f"FAIL: {len(failures)} record(s) have no place: {failures[:5]}")
    if failures or both:
        return 1
    print("PASS: every record version has exactly one place")
    return 0


if __name__ == "__main__":
    sys.exit(main())
