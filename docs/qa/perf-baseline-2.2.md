# Performance and crash baseline: Dormer 2.2

Measured 2026-11-01 on tag `v2.2` (856c318, the same commit as `origin/main` at that time), Debug build, 5 iterations per test, one install per device. This is the yardstick for 2.3: run `scripts/qa/perf_check.sh` on the same devices and compare with `scripts/qa/perf_compare.py`.

## How to repeat it

```bash
scripts/qa/perf_check.sh --label v2.3-iphone16plus --device 00008140-000C0226149B001C
scripts/qa/perf_check.sh --label v2.3-iphone16plus-idle --derived-label v2.3-iphone16plus --only testIdleTodayCPU --device 00008140-000C0226149B001C
python3 -I scripts/qa/perf_compare.py \
  <2.2 results dir>/results.json,<2.2 idle dir>/results.json \
  <2.3 results dir>/results.json,<2.3 idle dir>/results.json --threshold 10
```

The script claims the device in the device-claims file and releases it on exit; it refuses a device someone else holds, BLV-Phone and the stale iPad Air pairing. `--sim iphone|ipad` boots a throwaway simulator through simboot (iOS 26.5). The 2.2 raw results (results.json, results.md, xcresult) are in `~/AgentScratch/landlordhours-perf/2026-11-01/<label>/`; that folder is swept after 14 days, so the tables below are the durable copy.

## Devices and what ran

| Device | OS | Run |
|---|---|---|
| Dina's iPhone 16 Plus (00008140-000C0226149B001C) | iOS 26.6.2 | 7 of 7 tests passed |
| iPad 10th gen (00008101-001C5DE43E2BA01E) | iPadOS 27.0.1 | 7 of 7 passed |
| iPad mini 5 (00008020-001D059A3EA1402E) | iPadOS 26.7.1 | 7 of 7 passed |

Observed: the first attempts at the start of the session were skipped because every device had an open claim from another session. They freed up later and the runs above were claimed and released cleanly. No app, data or build was deleted on any device. A simulator run (iPhone 16 Plus, iOS 26.5) also passed but is not part of the baseline: simulators produce no hitch metrics and their memory and timing track host load.

## Baseline (median of 5; sd in brackets)

| Measure | iPhone 16 Plus | iPad 10th gen | iPad mini 5 |
|---|---|---|---|
| Cold launch: AppLaunch (s) | 0.5578 (sd 0.11) | 0.6831 (sd 0.014) | 0.7076 (sd 0.34) |
| Cold launch: first frame, responsive (s) | 0.6334 (sd 0.1) | 0.7577 (sd 0.017) | 0.858 (sd 0.43) |
| Cold launch to Today selected, clock (s) | 3.08 (sd 0.17) | 3 (sd 0.019) | 3.217 (sd 0.39) |
| Cold launch peak mem (MB) | 73.94 (sd 0.28) | 68.47 (sd 0.077) | 66.6 (sd 0.79) |
| Tab lap Today>Inbox>Records>Rentals>Today clock (s) | 16.12 (sd 0.18) | 15.74 (sd 0.063) | 18.08 (sd 0.2) |
| Tab lap peak mem (MB) | 118.8 (sd 0.01) | 108.6 (sd 5.8) | 110.1 (sd 0.019) |
| Tab lap hitch ratio (ms/s) | 0 (sd 0) | 0 (sd 0) | 0 (sd 0) |
| Records scroll occasional: dragging fps | 51.93 (sd 0.45) | 44.89 (sd 2.4) | 52.18 (sd 0.52) |
| Records scroll occasional: decel fps | 59.16 (sd 0.022) | 51.41 (sd 2.8) | 58.76 (sd 0.045) |
| Records scroll occasional: hitch ratio (ms/s) | 0 (sd 0) | 0 (sd 0) | 0 (sd 0) |
| Records scroll occasional: peak mem (MB) | 40.62 (sd 0.031) | 35.62 (sd 0.048) | 32.52 (sd 0.032) |
| Records scroll frequent: dragging fps | 52.62 (sd 0.55) | 51.3 (sd 2.8) | 52.9 (sd 3.2) |
| Records scroll frequent: decel fps | 59.22 (sd 0.31) | 57.09 (sd 0.78) | 56.71 (sd 1.1) |
| Records scroll frequent: hitch ratio (ms/s) | 0 (sd 0) | 0 (sd 0) | 0 (sd 0) |
| Records scroll frequent: peak mem (MB) | 47.43 (sd 0.058) | 53.63 (sd 0.065) | 47.5 (sd 2.9) |
| Open Log time clock (s) | 4.512 (sd 0.016) | 4.234 (sd 0.069) | 4.561 (sd 0.049) |
| Open Log time hitch ratio (ms/s) | 0 (sd 0) | 0 (sd 0) | 0 (sd 0) |
| Export PDF clock (s) | 15.6 (sd 0.024) | 15.74 (sd 0.05) | 16.83 (sd 0.14) |
| Export PDF peak mem (MB) | 48.83 (sd 0.15) | 52.45 (sd 3.4) | 40.57 (sd 0.02) |
| Idle Today 20 s: CPU time (s) | 0 (sd 0.00019) | 0 (sd 0.00024) | 0 (sd 0.00045) |
| Idle Today peak mem (MB) | 42.78 (sd 0.016) | 42.34 (sd 0.58) | 41.47 (sd 0.044) |

How to read it. "Clock" rows are XCUITest wall time and include the framework's wait-for-idle after each tap, so they are good for comparing builds and poor as absolute latency. Launch rows (`AppLaunch`, first frame responsive) come from the OS launch metric and are real. Hitch ratio is the whole-app XCTHitchMetric (iOS 26+); 0 is a measured zero, and the frame-rate rows (52 to 59 fps) show the metric was alive. Peak memory is the app process's peak physical footprint in a Debug build. The Records "occasional" seed has few rows, so its scroll is short; "frequent" is the longer list. Export PDF runs on the frequent seed because the free occasional seed opens the paywall.

## Suggested pass thresholds for 2.3

A 2.3 result fails if any of these is true, measured on the same device with the same script:

1. Any crash: a `.ips` for LandlordHours/Dormer during the run, a failed or crashed test, or a new crash signature in field data.
2. Any gating median is more than 10% worse than the table above (`perf_compare.py` does this: clock time, launch durations, peak and absolute memory up; scroll frame rate down).
3. Whole-app or scroll hitch time ratio over 5 ms/s (baseline is 0, so a percentage rule cannot work).
4. Idle Today CPU over 0.05 s in 20 s (baseline is under 0.001 s). This is the check for the iPad CPU reports below.

Fail-above values (baseline x 1.10) for the main rows:

| Measure | iPhone 16 Plus | iPad 10th gen | iPad mini 5 |
|---|---|---|---|
| AppLaunch (s) | 0.61 | 0.75 | 0.78 (noisy, sd 0.34: rerun once before failing; hard cap 1.0) |
| First frame, responsive (s) | 0.70 | 0.83 | 0.94 |
| Launch to Today, clock (s) | 3.39 | 3.30 | 3.54 |
| Launch peak memory (MB) | 81.3 | 75.3 | 73.3 |
| Tab lap clock (s) | 17.7 | 17.3 | 19.9 |
| Log time open, clock (s) | 4.96 | 4.66 | 5.02 |
| Export PDF clock (s) | 17.2 | 17.3 | 18.5 |
| Records scroll, frequent, decel fps (floor) | 53.3 | 51.4 | 51.0 |
| Records scroll, occasional, drag fps (floor) | 46.7 | 40.4 | 47.0 |

Five iterations is a small sample. Treat a borderline failure (under 15% and inside two standard deviations) as "rerun once"; a second miss fails.

## Field data (App Store Connect, pulled 2026-11-01, app 6759508794)

Observed:
- Version 2.2 is READY_FOR_DISTRIBUTION. Six builds carry marketing version 2.2 (2026102701 to 2026102803, uploaded 27 and 28 Oct); the newest is 2026102803. Which of those is the one on sale was not checked.
- TestFlight crash submissions: total 0, for the whole app and for build 2026102803. TestFlight feedback submissions: total 0.
- Performance diagnostics (hangs, disk writes, launches) for build 2026102803: 0 signatures. Performance metrics for that build: empty. App performance overview: no categories, no regressions, no top hang, launch or disk-write points.
- The same requests for the three previous builds return HTTP 404 "no resource", which is Apple's answer for builds without metrics data.

Reading it: every call returned 200 with the same credentials that listed the builds, so the data is accessible and genuinely empty, not blocked. Empty is not the same as clean. Two limits make this "no signal" instead of "no crashes": the API only exposes crashes users send through TestFlight, and Apple only computes hang, launch and disk metrics once enough opted-in users have the build. Production crash reports for the App Store build are in Xcode Organizer (Crashes) only, which an agent cannot read; that check is Brian's.

## Device crash logs (filtered to LandlordHours / Dormer only)

Observed, by listing each device's crash-log domain and copying only matching files:
- Dina's iPhone 16 Plus: 697 entries, none for this app.
- iPad mini 5: 85 entries, none for this app.
- iPad 10th gen: 181 entries, 4 for this app, all `cpu_resource` reports (not crashes), all from 26 Oct 2026 (14:10, 14:24, 17:05, 17:46), app version 2.0.1 build 2026102101, iPadOS 27.0.1. Each says "cpu usage", action taken none, 90 s of CPU inside a 180 s window. The heaviest stack is the main thread inside the SwiftUI/UIKit update cycle (UpdateCycle frames). The stacks are unsymbolicated as pulled; no dSYM was matched to build 2026102101.
- Mac simulator crash reports for the app during the perf runs: none.
- Copies of the four reports: `~/AgentScratch/landlordhours-perf/2026-11-01/devcrash/ipad10/`.

Inferred, not proven: the four reports point at sustained main-thread SwiftUI update work (an animation or state loop) on iPad in build 2026102101. The 2.2 idle-Today test shows about 0 s CPU over 20 s on all three devices, so it did not reproduce on idle Today with mock data. It has not been checked on the other screens or with real data. The `testIdleTodayCPU` test exists to catch a return of this.

## Known limits of this baseline

- Debug builds with DEBUG-only launch fixtures (`-LHMockScenario`), so the numbers are higher than a Release build. Compare only like with like.
- One device per model, 5 iterations, host load not controlled (other agents were testing during the runs).
- The iPhone is iOS 26.6.2 and the iPad 10th gen is iPadOS 27.0.1, so the "iPad" baseline is on a different OS from the iPhone.
- The first iPad mini result file records test rc 127 because `perf_check.sh` was edited while it ran; the xcresult itself shows 6 of 6 passed (the idle test ran separately and passed). It is not a test failure.
