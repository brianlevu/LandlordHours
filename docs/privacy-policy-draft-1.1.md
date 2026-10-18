# LandlordHours Privacy Policy (DRAFT for 1.1, not published)

Effective date: [CONFIRM: date this goes live]

LandlordHours ("we", "the app") helps you track rental property hours. This page says what stays on your device, what leaves it, and who sees it.

## What stays on your device and in your iCloud

Your time entries, properties, notes, addresses, receipts and reports are yours. They live on your device. If iCloud is on, your entries, properties and settings also sync to your own private iCloud account. Receipt photos stay on this device and are not synced. We run no server that stores them. We cannot read them.

## The note-to-fields feature runs on your device

When you type or dictate a note, the app reads it on your device to suggest a category, property and hours. Nothing is sent anywhere for this. We do not use a third-party AI service. Dictation uses Apple's speech recognition. On most recent iPhones it runs on the device; on some older devices Apple may process the audio on its servers.

## Anonymous usage analytics (PostHog)

The app sends anonymous usage events to PostHog (us.i.posthog.com). Examples: app opened, entry logged (and whether it was manual, timer, voice or calendar), property added, report viewed, export shared (PDF or CSV), paywall viewed, onboarding finished.

Events use a random ID made by the app. They never include your notes, property names, addresses, receipts, name or email.

We do not use session replay or automatic screen and tap capture. We do not use analytics for advertising or tracking across other apps.

Like any internet request, a request to PostHog may include standard network metadata, such as your IP address. [CONFIRM: is "Discard client IP data" turned on in the PostHog project settings? If yes, say "PostHog is set to discard IP addresses". The app code does not control this.]

You can turn this off at any time: Settings, Privacy, "Share Anonymous Usage Data". [CONFIRM: events already sent before opt-out stay in PostHog; say how long we keep them: ___ months.]

## Purchases

Apple handles all payments. We never see your card or Apple ID. We use RevenueCat to see purchase activity for analytics. The app uses a random RevenueCat ID, not your name or email. RevenueCat receives your App Store purchase records for this app (such as product, price and purchase date). It does not receive your notes, properties or hours. RevenueCat only starts if "Share Anonymous Usage Data" is on when the app launches. [CONFIRM: if a user opts out mid-session, RevenueCat keeps running until the next launch. Fix in code, or accept and keep this wording.]

## Sign in with Apple

Signing in is optional. If you do, the app gets a private user ID from Apple, and your name or email only if you choose to share them. These stay on your device and in your iCloud. [CONFIRM: we do not send them to PostHog or RevenueCat. Verify before publishing.] You can also use the app on this device only, with no sign-in.

## No ads, no sale of data

We do not run ads. We do not sell or rent your data. We do not share it with data brokers.

## Permissions

The app asks first before using notifications, calendar, location or the microphone and speech recognition. Each is optional. [CONFIRM: list matches the final 1.1 permission prompts.] Calendar and location data are used on your device to suggest entries. They are not sent to us.

## Delete your data

In Settings, choose "Delete Account and Data" (or "Delete All Data" if you use the app without signing in). This removes your data from the device, including receipt photos, and from your iCloud copy. If iCloud is unreachable, the app tells you, and iCloud copies can be removed later. Deleting the app removes the on-device copy.

You can export your records any time as PDF or CSV.

Analytics are anonymous and not linked to you, so we cannot look up or delete one person's events. [CONFIRM: acceptable wording for access/deletion requests (GDPR/CCPA). Do we want a contact route to request removal of the random ID?]

## Children

The app is not for children under 13. We do not knowingly collect data from them.

## Changes

If this policy changes, we will update this page and the date above.

## Contact

support@landlordhours.com

---

## Notes for Brian (remove before publishing)

- Old policy claimed "no analytics", "no third-party services", and "AI processed locally or through privacy-preserving methods". The first two are false for 1.1 (PostHog, RevenueCat). Publish this before or with 1.1.
- Also stale: landing-page/index.html AI claims, App Store 1.0.4/1.0.5 descriptions ("AI turns it into a structured entry"). Not changed.
- App Privacy label should match: Usage Data / Product Interaction (not linked, not tracking), Purchases (not linked, not tracking). Union with PostHog and RevenueCat SDK manifests per harness rule.
- [CONFIRM] the PostHog project is US cloud and what retention is set.
