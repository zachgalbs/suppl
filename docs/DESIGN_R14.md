# R14: durable reminders

**Decision:** ship a budgeted one-shot queue, a final heads-up notification that is moved on every re-plan, and re-planning on every way the app gets to run. Repeating dose reminders stay out. APNs is the long-term fix and is future work.

## The problem

Reminders are one-shot local notifications with dated ids (`suppl.<yyyy-MM-dd>.<moment>[.f<n>|.s]`). Each re-plan rolls the queue forward, but only when the app runs. Before this change the queue was capped at 48 requests and covered at most 7 days, so a six-moment Extra Help routine with quiet hours off ran out after about four days, and nothing told the user. The pre-v1 build used repeating daily triggers that never stopped. That is the regression R14 records.

The rules any fix must keep:

1. Never a duplicate reminder for the same dose.
2. Nothing fires for a dose already marked Taken or Skipped.
3. Quiet hours, weekday frequency and clinician-directed timing hold.
4. Never more than iOS's 64 pending requests, and the warning always fits.
5. With zero app launches, the user keeps getting usual-time reminders or gets a warning before the last one. Never silence without warning.

## What the platform guarantees

| Claim | Apple source |
|---|---|
| The system keeps only the soonest-firing 64 local notifications and discards the rest. Stated on the legacy `UILocalNotification` page; the UserNotifications pages don't restate a different number, so we treat 64 as binding and assume the *farthest* requests are the ones lost. | [UILocalNotification](https://developer.apple.com/documentation/uikit/uilocalnotification) |
| A request stays pending until its trigger fires or the app cancels it. A repeating calendar trigger is rescheduled by the system after each delivery. | [Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) |
| A calendar trigger is built only from date components plus a `repeats` flag. A repeating request keeps delivering until the app explicitly removes it. There is no start-date parameter and no way to skip one occurrence. | [UNCalendarNotificationTrigger](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger), [init(dateMatching:repeats:)](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger/init(datematching:repeats:)) |
| A repeating time-interval trigger also delivers until it's explicitly removed. | [UNTimeIntervalNotificationTrigger init(timeInterval:repeats:)](https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger/init(timeinterval:repeats:)) |
| Adding a request whose identifier matches a pending one replaces it. | [UNNotificationRequest.identifier](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier) |
| `removePendingNotificationRequests(withIdentifiers:)` runs asynchronously, on a secondary thread. | [removePendingNotificationRequests(withIdentifiers:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)) |
| Tapping a notification action launches the app in the background and calls the delegate's `didReceive`. A tap on the notification itself reports the default action. | [Handling notifications and notification-related actions](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions) |
| A swipe-to-dismiss reaches the app only if the category sets `customDismissAction`. suppl. doesn't, so a dismissal never runs the app. | [UNNotificationCategoryOptions.customDismissAction](https://developer.apple.com/documentation/usernotifications/unnotificationcategoryoptions/customdismissaction) |
| `BGAppRefreshTask` needs the `fetch` background mode. `earliestBeginDate` only promises "not sooner", not a launch. One refresh request can be queued, and resubmitting replaces it. | [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate), [submit(_:)](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:)) |
| Background App Refresh can be turned off by the user and is turned off automatically in Low Power Mode. | [UIApplication.backgroundRefreshStatus](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus) |
| HealthKit background delivery wakes the app at most once per frequency period when matching samples change. Observer queries belong in `didFinishLaunching`, and the update handler must be called or HealthKit backs off and eventually stops. | [enableBackgroundDelivery(for:frequency:withCompletion:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)) |
| Background (silent) pushes are low priority, not guaranteed, throttled (Apple suggests no more than two or three an hour), and discarded if the app was force-quit. | [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) |

So no background path is guaranteed to run. A fix has to stay safe if the app never runs again.

## Options compared

### A. Budget the request cap (shipped)

- **Limit.** 64 total. Two slots are always reserved: one for the heads-up and one for the Debug test reminder. The engine gets the rest (62), minus any pending request it doesn't manage. On the first launch after upgrading, the old build's repeating `suppl.<slot>` and `suppl.followup.<slot>` requests (up to 10) are counted as still pending, even though they're being removed, because removal is asynchronous. The engine gets 52 on that pass and 62 afterwards.
- **Priority.** (1) snoozes the user asked for and follow-ups due within 24 hours, (2) initial reminders, soonest first, (3) later follow-ups, only if room is left. Within each tier soonest wins, so the farthest reminders give way. A follow-up whose initial was cut is dropped, so there's no "Still open" about something never sent.
- **Horizon.** Initials are planned up to 14 days ahead, budget permitting (it was 7). A light routine now lasts two weeks with zero launches. The busiest routine lasts about eight and a half days (eight full days of every moment), up from about four. A longer horizon *alone* would not help: the cap, not the horizon, was the binding limit, and with no warning the queue would still end silently.
- **Runtime guard.** Before adding a new identifier, the scheduler re-reads what iOS reports as pending, counting the two reserved slots as taken. If 64 is reached, it skips the farthest additions. Because removal is asynchronous, this re-read can only over-count, which errs safe. The heads-up is computed from what iOS actually accepted, not from what was planned.
- **Rules.** Ids are still one per dose day, moment and stage, so nothing duplicates. Taken and Skip still remove the group's pending requests and re-plan. Budgeting only decides *which* already-valid reminders go in, so quiet hours, weekdays and clinician-directed timing are untouched.

### B. Final heads-up notification (shipped)

- One request, `suppl.headsup`. Title "suppl.", body "Open suppl. to keep your reminders coming." No category, so there's no Taken, Snooze or Skip. It names no supplement, so it reads the same with lock-screen privacy on.
- **When.** It reuses the fire time of a planned initial reminder outside quiet hours: the latest one at least 24 hours before the last planned initial, or the earliest if the queue is shorter than that. Reusing a time that already passed quiet-hours and window rules means it never adds a new time of day. Coverage only ever ends after the last planned initial, so the warning always comes before silence. In the busiest routine it comes a full day early.
- **Replaced on every re-plan.** It uses the same identifier, so adding it replaces the old one, and it's skipped when unchanged. If nothing is planned, it's removed. Anyone whose app runs at least every few days (including through notification actions) never sees it.
- **Tap.** Opens the app. `ReminderActions` re-plans for it, and launching re-plans anyway.
- **Rules.** It isn't a dose reminder, so it can't duplicate one or fire "after Taken" for a dose. It fits because its slot is reserved.

### C. Re-plan on every execution path (shipped)

Every way the app gets to run now rolls the queue forward and moves the heads-up:

| Path | Before | Now |
|---|---|---|
| Notification action (Taken, Snooze, Skip) | Re-plans | Unchanged |
| Tap on a reminder or the heads-up (warm) | Re-plans on `scenePhase == .active` | Also re-plans directly for the heads-up |
| Any launch: cold, background, HealthKit, BG task, action | Not guaranteed: SwiftUI's `onChange` runs for the initial value only when asked to ([onChange(of:initial:_:)](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg)), and launch itself only re-planned if Pro changed | `didFinishLaunching` re-plans and re-submits the refresh task |
| HealthKit background delivery | Re-plans with fresh signals | Unchanged; it also helps free users |
| `BGAppRefreshTask` | Re-plans; resubmitted when the task runs or the app backgrounds | Also resubmitted at every launch |
| Foreground | Re-plans | Unchanged |
| Time zone or clock change | Re-plans | Unchanged |

None of these paths is guaranteed (see the table above), which is why A and B must be safe by themselves.

### D. Repeating triggers (rejected)

1. **Parallel daily repeating usual-time alarm per moment, alongside the smart one-shots.** It duplicates: when a smart reminder moved (workout, late wake, calendar gap), both fire. It fires after Taken: a repeating request can't skip one occurrence, only be removed, and removing it also removes every future day. Violates rules 1 and 2.
2. **Repeating usual-time triggers instead of one-shots, removed when Taken and re-added later.** A repeating calendar trigger has no start date, so re-adding it at Taken time makes it fire at the next matching time, which is still today if the usual time hasn't passed. Waiting to re-add it needs the app to run after that time, and nothing guarantees that. Smart timing and follow-ups are also lost. Violates rule 2 (or rule 5 if it is never re-added).
3. **Weekly repeating triggers (weekday + time) as a fallback tail beyond the one-shot horizon.** A weekly trigger also matches dates inside the horizon, so it duplicates that weekday's one-shot unless the one-shot is left out, and then a dose taken early or moved by context still gets the repeating alarm. Again there's no start date and no way to skip one occurrence. Violates rules 1 and 2.
4. **Repeating time-interval trigger (every 24 h).** It starts counting when it's scheduled, can't start after the horizon, and drifts against wall-clock time across DST. Same skip and remove problem. Violates rules 1 and 2.
5. **Repeating heads-up (non-dose).** No dose rule is broken, but it would nag daily even while the queue is healthy, because a repeating trigger can't start "after the queue". A one-shot heads-up that is moved on every re-plan gives the same safety without the noise.

### E. APNs (future work)

A server that knows each user's schedule can send alert pushes indefinitely. It could also send a background push to wake the app and re-plan, though Apple says those are throttled and not guaranteed ([Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app); provider setup in [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)). The cost: accounts or device tokens, a backend holding supplement schedules (health-adjacent data off the phone, contradicting `PRIVACY.md` today), push credentials, and duplicate suppression across local and remote copies. It's out of scope for v1, which has no backend besides the WHOOP token broker. It's the right fix once a backend exists.

## Trade-offs accepted

- With zero launches, reminders still stop. The difference is that they stop after 8 to 14 days instead of about 4, and only after a clear warning.
- In the busiest routines, follow-ups more than 24 hours out give way to initials until the next re-plan.
- The heads-up rides on a reminder's time, so on that one occasion the user sees two notifications at once.
- If every planned initial is inside quiet hours (only possible for bedtime reminders exempted from them), the heads-up shares that bedtime reminder's time.
- iOS's 64 limit is documented on a legacy page. If Apple ever lowered it, the runtime guard would still not exceed what iOS reports, but the reserved-slot arithmetic would need updating.

## Tests

- `SupplCore/Tests/SupplCoreTests/EngineDurabilityTests.swift`: budget arithmetic and foreign counts; the six-moment Extra Help worst case at 0 and 10 foreign requests; a zero-launch simulation (every moment covered for eight days, heads-up at least a day before the first missing reminder); the heads-up shares a planned time and stays outside quiet hours; Taken and Skip leave nothing pending; no duplicate initials; weekday and clinician timing under the budget; follow-ups never outlive their initial; snoozes are kept.
- `SupplTests/DurableRemindersTests.swift`: the same worst case through the app's real request builders, including the upgrade pass with the old build's requests still pending, the 64 limit with the test slot, quiet hours, Taken and Skip, and the heads-up's identity (no category, no plan ids, replaced in place).
- `EngineHorizonTests`: a week of initials and near-term follow-ups survive the cap; the default horizon is two weeks.
