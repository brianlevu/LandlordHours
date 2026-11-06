# fastlane/metadata

Snapshot of the live App Store listing (v2.3), refreshed 2026-11-06 from App Store Connect.
Canonical metadata lives in `/metadata`, pulled with `asc metadata pull`. Re-pull before any listing or ASO work; never trust this snapshot alone.
The `release` lane in `fastlane/Fastfile` uploads this folder (`skip_metadata: false`), so keep it in step with `/metadata` or ASC gets overwritten.
`copyright.txt` is the source for the App Store copyright line.
