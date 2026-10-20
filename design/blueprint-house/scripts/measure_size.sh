#!/bin/bash
# Compiled-size cost of Assets.xcassets/Blueprint: actool with and without it, universal and thinned (iPhone 16 Pro, @3x).
# usage: scripts/measure_size.sh <repo_root> <scratch_dir>
set -e
ROOT="$1"; S="$2"
mkdir -p "$S/base"
rsync -a --delete --exclude Blueprint "$ROOT/Assets.xcassets/" "$S/base/Assets.xcassets/"
run() { # catalog out [thin]
  mkdir -p "$2"
  if [ -n "$3" ]; then
    xcrun actool "$1" --compile "$2" --platform iphoneos --minimum-deployment-target 17.0 --app-icon AppIcon \
      --filter-for-device-model "$3" --filter-for-device-os-version 18.0 --output-partial-info-plist "$2.plist" >/dev/null
  else
    xcrun actool "$1" --compile "$2" --platform iphoneos --minimum-deployment-target 17.0 --app-icon AppIcon \
      --output-partial-info-plist "$2.plist" >/dev/null
  fi
  stat -f %z "$2/Assets.car"
}
b=$(run "$S/base/Assets.xcassets" "$S/c_base"); w=$(run "$ROOT/Assets.xcassets" "$S/c_with")
bt=$(run "$S/base/Assets.xcassets" "$S/c_base_3x" iPhone17,1); wt=$(run "$ROOT/Assets.xcassets" "$S/c_with_3x" iPhone17,1)
bt2=$(run "$S/base/Assets.xcassets" "$S/c_base_2x" iPad11,1); wt2=$(run "$ROOT/Assets.xcassets" "$S/c_with_2x" iPad11,1)
python3 -c "
b,w,bt,wt,bt2,wt2=$b,$w,$bt,$wt,$bt2,$wt2
M=1e6
print(f'universal Assets.car: {b/M:.2f} MB -> {w/M:.2f} MB  (+{(w-b)/M:.2f} MB)')
print(f'thinned iPhone @3x:  {bt/M:.2f} MB -> {wt/M:.2f} MB  (+{(wt-bt)/M:.2f} MB)')
print(f'thinned iPad mini @2x: {bt2/M:.2f} MB -> {wt2/M:.2f} MB  (+{(wt2-bt2)/M:.2f} MB)')
print(f'source PNGs on disk: see du of Assets.xcassets/Blueprint')
"
