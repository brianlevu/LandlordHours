# Session Handoff - Xcode 27 Readiness and LandlordHours Roadmap

Date: 2026-06-22
Project: `/Users/brian/Projects/LandlordHours`

## Current Toolchain State

- Active Xcode: `/Volumes/Home/Applications/Xcode.app/Contents/Developer`
- Current version: Xcode 26.5, build 17F42
- Current iPhone SDK: 26.5
- Current simulator runtime used this session: iPhone 17, iOS 26.5
- Project deployment target: iOS 17.0
- Xcode 27 beta is not installed/selected in this workspace yet.

## Storage Direction

Brian wants Xcode and large development data on the external SSD at `/Volumes/Home`, not the small internal drive.

Recommended target layout:

```text
/Volumes/Home/Applications/Xcode.app
/Volumes/Home/Applications/Xcode-27-beta.app
/Volumes/Home/XcodeStorage/DerivedData
/Volumes/Home/XcodeStorage/Archives
/Volumes/Home/XcodeStorage/CoreSimulator
/Volumes/Home/XcodeStorage/DeviceSupport
```

Do not move keychain/signing secrets wholesale. Keep Xcode preferences and signing identity management normal unless there is a specific reason.

Known current large internal development folders from this session:

- `~/Library/Developer/CoreSimulator/Devices`: about 17G
- `~/Library/Developer/Xcode/iOS DeviceSupport`: about 6.4G
- `~/Library/Developer/Xcode/DerivedData`: about 1.1G
- `~/Library/Developer/Xcode/Archives`: about 469M
- `~/Library/Developer/XcodeBuildMCP/workspaces`: about 772M

## Xcode 27 Goal

Install Xcode 27 beta on the SSD, keep Xcode 26.5 available, and verify that Codex/XcodeBuildMCP can build, test, run simulator builds, archive, and preserve App Store/TestFlight upload capability.

Preferred approach:

- Install Xcode 27 beta as `/Volumes/Home/Applications/Xcode-27-beta.app`.
- Keep current Xcode as `/Volumes/Home/Applications/Xcode.app`.
- Switch with `xcode-select` only after verifying installation.
- Do not raise the whole app minimum to iOS 27 immediately.
- Use iOS 27 APIs behind availability checks where practical.

## Current LandlordHours Work Completed

### Track screen design and flow

Files touched:

- `Sources/Views/TimeLogView.swift`
- `UITests/LandlordHoursUITests.swift`
- `docs/design-improvement-backlog.md`

What changed:

- Reframed Track Log mode as a focused evidence composer.
- Added an evidence draft preview for property, category, and hours.
- Removed duplicate empty-state AI copy.
- Tightened note field height.
- Added a UI regression test proving typing stays in the Track composer and does not trigger iOS Search.
- Improved expanded details by making Date and Person separate full-width rows.
- Rebuilt the Person selector as a larger, icon-backed segmented control for Self/Spouse.

### Text-to-fields parsing

Files touched:

- `Sources/Services/AITimeEntryService.swift`
- `Tests/LandlordHoursTests.swift`

What changed:

- Fixed natural language hours so phrases like `an hour`, `one hour`, `half hour`, `15 minutes`, and `two hours` are explicit durations.
- Fixed the reported bug where `Painting the porch for an hour` was parsed as `2.0h` due to the paint estimate path.
- Added parser regression tests:
  - `Painting the porch for an hour` -> `1.0h`
  - `painted trim for two hours` -> `2.0h`

## Verification Completed

Before this handoff:

- Focused parser + Track UI tests passed: 15/15.
- Full simulator suite passed: 70/70.
- Build/run with XcodeBuildMCP succeeded on iPhone 17 simulator.

Useful evidence:

- Track milestone screenshots:
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/08-occasional-track.png`
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/13-frequent-track-pro.png`
- Backlog:
  - `/Users/brian/Projects/LandlordHours/docs/design-improvement-backlog.md`

## Roadmap After Xcode 27 Setup

1. Re-run full build/test under Xcode 27 beta.
2. Verify simulator and physical iOS 27 beta device workflow.
3. Add a `VoiceEntryService` abstraction.
4. Build Apple-native voice logging:
   - iOS 27-first implementation if the Xcode 27 SDK exposes newer speech APIs worth using.
   - Keep iOS 26 and earlier fallback where possible.
   - Feed transcript into the existing local parser.
   - Never require MiniMax for the core voice-to-fields flow.
5. Continue Impeccable design roadmap:
   - Next major screen: `PropertiesView.swift`.
   - Then first-time/onboarding capture correctness.
   - Then Reports bottom inset.

## Important Constraints

- Keep changes local-first and privacy-preserving.
- Do not introduce remote AI as a required path for tax-sensitive text parsing.
- Do not remove the local parser; improve it with confidence rules and phrase coverage.
- Preserve broad compatibility unless Brian explicitly decides to raise the minimum OS.
- Do not break App Store/TestFlight upload capability.
- When touching UI, follow `AGENTS.md` and `docs/design-audit-playbook.md`.
- Use `impeccable` for UI/design work.

## Resume Prompt For This Project

Use this when returning to LandlordHours after the Xcode 27 setup:

```text
We are continuing `/Users/brian/Projects/LandlordHours`.

First read:
- `/Users/brian/Projects/LandlordHours/AGENTS.md`
- `/Users/brian/Projects/LandlordHours/docs/design-audit-playbook.md`
- `/Users/brian/Projects/LandlordHours/docs/design-improvement-backlog.md`
- `/Users/brian/Projects/LandlordHours/docs/session-handoff-2026-06-22-xcode27-roadmap.md`

Context:
- Xcode 27 beta setup should now be complete on `/Volumes/Home`.
- Verify `xcodebuild -version`, `xcode-select -p`, available SDKs, and simulator runtimes before making code changes.
- Re-run full simulator tests under the selected Xcode.
- Current app roadmap is iOS 27-forward, but do not raise minimum OS unless explicitly approved.
- Continue the roadmap by implementing Apple-native voice logging through a `VoiceEntryService` abstraction, feeding transcripts into the existing local parser.
- Keep the core text-to-fields flow local-first; MiniMax is optional only for future fallback.
- After voice setup, continue Impeccable roadmap with Properties screen polish.

Recent changes to preserve:
- Track evidence composer redesign.
- Parser fix for `Painting the porch for an hour` -> `1.0h`.
- Full-width Person selector in Track details.
- UI regression test for typing staying in Track composer.

Before marking complete:
- Build/run on simulator.
- Run full tests.
- Capture visual evidence for changed screens.
- Update `docs/design-improvement-backlog.md` and this handoff if the roadmap changes.
```
