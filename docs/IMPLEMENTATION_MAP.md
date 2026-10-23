# Implementation map

Status of every SPEC.md item and every BLUEPRINT §28 checklist line on branch `feat/v1-smart-timing`.

Statuses: **Implemented** · **Partial** · **Not started** · **Blocked (external)** · **Needs clinical review** · **Needs legal or App Store review**.

"Implemented" means it compiles in macOS CI and its logic has tests. Nothing in this branch has run on a real iPhone yet (see the PR's "How to test").

## SPEC.md (v1)

| Item | Status | Where |
|---|---|---|
| Onboarding: name | Implemented | `Suppl/Onboarding/NameStep.swift` |
| Onboarding: age, adults only | Implemented | `Suppl/Onboarding/AgeStep.swift` (under 18 stops; stores `profile.isAdult`, `profile.birthYear`) |
| Onboarding: add supplements | Implemented | `Suppl/Onboarding/AddSupplementsStep.swift`, `Suppl/Home/SupplementSearchView.swift` |
| Onboarding: usual meal times, wake/sleep | Implemented | `Suppl/Onboarding/TimesStep.swift` (Zach's time rows) |
| Onboarding: notification intensity | Implemented | `Suppl/Onboarding/StyleStep.swift` (Gentle / Balanced / Extra Help) |
| Add supplements: search | Implemented | `SupplCore/Sources/SupplCore/Catalog/`, `Suppl/Resources/catalog.json` (66 ingredients) |
| Add supplements: manual entry (name, brand, dose, unit, frequency, with food) | Implemented | `Suppl/SupplementForm.swift` (+ post-workout moment, clinician-directed flag, notes) |
| Home: greeting, list (name, dose, timing note), one daily tip | Implemented | `Suppl/HomeView.swift`, `Suppl/Home/StatusCard.swift`, `Suppl/Home/TipCard.swift`, `Suppl/Resources/tips.json` (44 sourced tips) |
| Supplement detail: edit / remove | Implemented | `Suppl/Home/SupplementDetailView.swift` |
| Reminders at usual meal times | Implemented | `SupplCore/.../Engine/ReminderEngine.swift`, `Suppl/Engine/NotificationScheduler.swift` |
| Taken / Snooze / Skip | Implemented | `Suppl/Engine/ReminderActions.swift`, `Suppl/Engine/Logs.swift` (`DoseLog`) |
| One follow-up max (Balanced) | Implemented | Engine follow-ups by intensity (Gentle 0, Balanced 1, Extra Help 2) |
| Apple Health: workouts | Implemented | `Suppl/Connectors/AppleHealthConnector.swift` (observer query + background delivery, best effort) |
| Apple Health: sleep | Implemented | same file; late wake shifts flexible wake/breakfast reminders |
| Apple Health: meals | Not started | Out of scope for this session (nutrition data) |
| Calendar to shift timing | Implemented | `Suppl/Connectors/CalendarConnector.swift` (busy times only) |
| StoreKit 2 subscription $7.99/mo, $39.99/yr | Implemented in code; Blocked (external) for TestFlight | `Suppl/Store/`, `Suppl/Paywall/`, `Suppl/Resources/Products.storekit`. Products must be created in App Store Connect |
| Rule: never diagnose / prescribe / double a dose | Implemented | Copy in `SupplCore/.../Copy/ReminderCopy.swift`; content tests reject claim words and "double" |
| Rule: no deficiency inference from wearables | Implemented | Workouts only re-time `postWorkout` plans; tested |
| Rule: free calendar slot is not eating; stale data is not live | Implemented | Conditional calendar copy; freshness checks on every signal; tested |
| Rule: safety info never paywalled | Implemented | Detail screen, catalog notes, rule notes are all free |
| Rule: no health data in analytics | Implemented | No analytics SDKs at all |
| Later: WHOOP | Partial / Blocked (external) | Full connector + token broker built; hidden until a WHOOP developer app and broker exist |
| Later: bottle scanning, AI chat, backend/accounts, Oura, nutrition apps, lab reports, mascot | Not started | Deliberately out of scope |

## BLUEPRINT §28 checklist

| Line | Status | Notes |
|---|---|---|
| Beautiful native iPhone application | Partial | SwiftUI with Zach's design tokens; not yet reviewed on a device |
| Complete onboarding | Partial | 11 of the blueprint's 16 screens. Skipped: goals, medications, health considerations, mascot, example notifications |
| Supplement scanning | Not started | Out of scope |
| Supplement search | Implemented | Ingredient-level catalog, typo-tolerant. No brand-level products |
| Supplement-list upload | Not started | Out of scope |
| Manual supplement entry | Implemented | |
| Verified saved supplement doses | Partial | The app stores and shows exactly what the user typed and never changes it. No label verification (needs scanning) |
| Structured evidence-backed knowledge engine | Partial; Needs clinical review | Catalog + rule model with ids, versions, sources, `reviewStatus: "unreviewed"` |
| Medication and supplement safety screening | Not started; Needs clinical review | No medication entry. Three supplement spacing rules exist but ship `enabled: false` |
| Context-aware reminder architecture | Implemented | Pure engine in `SupplCore` with ~100 tests; app scheduler diffs pending requests |
| Functional push notifications | Partial | Local notifications only. APNs out of scope |
| Taken, Snooze, and Skip actions | Implemented | |
| Gentle accountability | Partial | No shame copy, no-response stays unconfirmed. No streaks yet |
| Optional mascot | Not started | Stretch |
| Extremely simple home screen | Implemented | Status card, list, one tip |
| Daily educational insights | Implemented | 44 tips with sources; Needs clinical review |
| Full contextual AI chat | Not started | Out of scope |
| Explainable notification decisions | Implemented | `DecisionLog` + Why-now sheet (`Suppl/Home/WhyNowView.swift`), Recent reminders (Pro) |
| Optional data integrations with honest availability states | Implemented | Apple Health, Calendar. WHOOP shows "Not available yet" until configured |
| Graceful fallback without connected apps | Implemented | Usual times; equals the pre-v1 behaviour; tested |
| Monthly and yearly subscriptions | Implemented in code; Blocked (external) | App Store Connect products |
| Working purchase restoration | Implemented in code | `AppStore.sync()`; needs a sandbox test on device |
| Secure authentication | Not started | No accounts in v1 (nothing leaves the device) |
| Privacy controls | Implemented | Lock-screen privacy mode, per-connector disconnect, delete all data |
| Account deletion | Partial | No accounts; "Delete all data" clears everything local and WHOOP tokens |
| Accessibility support | Partial | Dynamic Type, VoiceOver labels, 44 pt targets in code; not audited on device |
| Automated testing | Implemented | 159 core tests, 11 app tests, 18 broker tests, all in CI |
| Clinical safety review of actionable rules | Needs clinical review | Every catalog entry, tip, and rule is `unreviewed` |
| Legal and privacy review | Needs legal or App Store review | `PRIVACY.md` is a draft; health claims and paywall copy need review |
| App Store submission readiness | Needs legal or App Store review | Privacy policy URL, App Privacy answers, subscription metadata, review notes |
