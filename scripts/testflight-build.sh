#!/bin/bash
# LandlordHours 2.0 -> TestFlight: archive, export, verify. Uploads ONLY with --upload.
# Archive step proven 2026-10-20 (Xcode 27.1, macOS 26A428). Export step is UNTESTED: first run, read the output.
# Needs: clean checkout of the branch you want to ship, run from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_ID=6759508794
KEY=~/.appstoreconnect/private_keys/AuthKey_QTQXKZ5CN8.p8
BUILD=$(date +%Y%m%d%H%M)   # same scheme as 1.0.x builds; never mix with Xcode Cloud's counter inside one version
OUT=~/AgentScratch/landlordhours/$(date +%F)/release-$BUILD
DD=~/tmp/DerivedData/landlordhours-release
[ -z "$(git status --porcelain)" ] || { echo "Dirty tree: commit or stash first"; exit 1; }
BV=$(sw_vers -buildVersion); case "$BV" in *[a-z]) echo "Beta macOS ($BV): do not build a store archive"; exit 1;; esac
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>G68NLC3DA3</string>
<key>signingStyle</key><string>automatic</string>
<key>destination</key><string>export</string>
<key>uploadSymbols</key><true/>
</dict></plist>
PL
SIGN=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID QTQXKZ5CN8 -authenticationKeyIssuerID ab32fd62-caed-497e-bb3f-d2b444bd74d7)
# System-only PATH: Homebrew rsync breaks -exportArchive (harness, Bee Buddy 1.9.1).
X() { env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild "$@"; }
X archive -project LandlordHours.xcodeproj -scheme LandlordHours -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$OUT/LandlordHours.xcarchive" -derivedDataPath "$DD" \
  CURRENT_PROJECT_VERSION="$BUILD" "${SIGN[@]}" > "$OUT/archive.log" 2>&1
X -exportArchive -archivePath "$OUT/LandlordHours.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${SIGN[@]}" > "$OUT/export.log" 2>&1
IPA=$(ls "$OUT"/export/*.ipa)
P=$(unzip -p "$IPA" 'Payload/*.app/Info.plist' | plutil -convert json -o - -)
echo "$P" | python3 -c "import json,sys; d=json.load(sys.stdin); print('version',d['CFBundleShortVersionString'],'build',d['CFBundleVersion'],'BuildMachineOSBuild',d['BuildMachineOSBuild'])"
echo "$P" | python3 -c "import json,sys,re; d=json.load(sys.stdin); assert d['CFBundleShortVersionString']=='2.0'; assert not re.search('[a-z]\$',d['BuildMachineOSBuild'])"
echo "IPA: $IPA"
if [ "${1:-}" = "--upload" ]; then
  ASC_TIMEOUT=90s asc builds upload --app "$APP_ID" --ipa "$IPA" --wait   # take the asc lock first (shipping.md)
else
  echo "Not uploaded. To upload: ASC_TIMEOUT=90s asc builds upload --app $APP_ID --ipa \"$IPA\" --wait"
fi
