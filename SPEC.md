# suppl.

iPhone app that reminds people to take the supplements they already use, at moments that make sense (meal, post-workout, free time) instead of fixed alarms.

## v1 (MVP)
- Onboarding: name, age (adults only), add supplements, usual meal times, wake/sleep, notification intensity
- Add supplements: search or manual entry (name, brand, dose, unit, frequency, with food?)
- Home: greeting, supplement list (name, dose, timing note), one daily tip
- Supplement detail: edit / remove
- Reminders: local notifications at usual meal times; Taken / Snooze / Skip; one follow-up max (Balanced)
- Apple Health (meals, workouts, sleep) + Calendar to shift reminder timing — optional
- Subscription via StoreKit 2: $7.99/mo, $39.99/yr

## Later
Bottle scanning, AI chat, backend/accounts, WHOOP, Oura, nutrition apps, lab reports, mascot.

## Rules
- Never diagnose, prescribe, change doses, or say to double a missed dose
- Don't infer deficiencies from wearable data
- Free calendar slot ≠ eating; stale data ≠ live data
- Safety info is never paywalled
- No health data in analytics

## Design
Calm, minimal, large text. Cream `#F8F6F0`, sage `#789575`, forest text `#344536`, lavender `#987E9F`. SF font, Dynamic Type. Wordmark: `suppl.`

## Open risk
Interviewees said they wouldn't pay. Validate before building much.
