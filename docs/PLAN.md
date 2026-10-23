# Build plan: v1 + smart timing

Branch `feat/v1-smart-timing` (from `origin/main` @ 94a61e5). Draft PR to `main` after the first green CI run. This file plus `docs/BUILD_LOG.md` is enough to resume the session.

## What's in the repo
- Matches the repo notes: one commit, 8 Swift files (788 lines), one `@Model` (`Supplement`), XcodeGen project, no tests, no CI, no README.
- Reminders are repeating daily triggers with ids `suppl.<slot>`; snooze schedules `suppl.followup.<slot>`. The new scheduler must remove those legacy ids on first run so old installs don't get double reminders.
- Skip and "tap the banner" record nothing; "taken" is a single `lastTakenAt`.
- `sharedContainer` only lists `Supplement`. New `@Model` types get added to that schema (new entity types and new properties with defaults are lightweight migrations).
- Navigation is one `NavigationStack` with a gear button that opens `SettingsView` as a sheet. No contradictions with the repo notes found.

## Environment
- git: on `feat/v1-smart-timing`, clean, pre-push guard installed (blocks main, force-push, branch deletion).
- gh: logged in, WRITE access, repo is public, token has `repo` + `workflow`. No workflows yet. Whether Actions is enabled is only knowable from the first push (the permissions API needs admin).
- Swift: not installed. swiftly download is reachable. Box is Debian 13 x86_64, 2 cores, ~7.7 GB RAM, so at most two Swift builds run at once.
- xcodegen: not installed. Will try building it from source on Linux; fallback is the CI `xcodeproj` artifact.
- Node 22 is present for the WHOOP broker and its `node --test` suite.

## Phases (as in the build prompt, with these adjustments)
1. **Foundation (me).** CI workflow first; `.gitignore`; `docs/BUILD_LOG.md`; `SupplCore` package with `Contracts.swift` and a trivial test; `project.yml` (local package, `SupplTests` target, entitlements, usage strings, URL scheme, BG task id, StoreKit config in scheme, xcconfig for WHOOP keys). Gate: CI green, app unchanged. Open draft PR.
2. **Parallel build (4 agents in worktrees).** Merge A → B → C → D, tests/CI after each.
3. **Integration (me).** `NotificationScheduler`, `DoseLog` / `DecisionLog`, actions, re-plan triggers, Why-now sheet, Pro gating, `SupplTests` mapping tests. Gate: CI green.
4. **Independent review** by a fresh agent on `git diff origin/main...HEAD`. Fix real findings, log the rest.
5. **Stretch** (streak, mascot, Oura boundary) only if 1 to 4 are green.
6. **Handoff**: BUILD_LOG, IMPLEMENTATION_MAP, PR description, final push.

Adjustments:
- The `Connector` protocol lives in `SupplCore/Contracts.swift` (Foundation-only, so it's shared and testable); the app implements it.
- Agents do not push branches. They commit in their local worktree; I merge and push. This keeps Zach's repo free of extra branches (I can't delete branches).
- Agents C and D can't compile on Linux. They re-check Apple API signatures before handing back, and I run batched CI fix rounds after merging each one.
- Keep the single `NavigationStack` + profile button pattern (no `TabView`).

## Subagent briefs
- **A, Engine**: `SupplCore/Sources/SupplCore/{Engine,Copy,Rules}/` + tests. Done: `swift test` green, 40+ cases covering every bullet in §4.2.
- **B, Catalog & content**: `SupplCore/Sources/SupplCore/Catalog/`, `Suppl/Resources/catalog.json`, `tips.json` + tests. Done: search tests green, JSON validated by a test, every entry has a source URL and `reviewStatus: "unreviewed"`.
- **C, Connectors**: `Suppl/Connectors/`, `server/whoop-broker/`. Done: broker `node --test` green, WHOOP hidden when unconfigured, code re-checked against Apple and WHOOP docs; compiles in CI after merge.
- **D, UI**: `Suppl/{Onboarding,Home,Profile,Paywall,Store}/`. Done: every screen has a preview with in-memory data; compiles in CI after merge.

## Risks and unattended handling
- Actions disabled or no macOS runner: log under "Needs a human", keep all logic in `SupplCore` with tests, say plainly in the PR that the app target is uncompiled.
- App-layer compile errors burn CI rounds: batch fixes, re-read API signatures before each push.
- Existing installs: no renamed or removed stored properties, keys, slot raw values, or notification category/action ids. Free tier keeps today's usual-time reminders, so testers never get worse behavior.
- Low RAM: long builds run detached with logs; max two concurrent Swift builds.
- Secrets: WHOOP client id and broker URL ship empty; the client secret lives only in the broker's env.
- Public repo: nothing from outside the repo (kit, blueprint, personal details) gets committed.

## Skipped on purpose
Bottle/label OCR, list upload, Ask Suppl chat, accounts/auth, any backend besides the WHOOP broker, lab reports, nutrition connectors, Google/Outlook calendars, APNs, analytics. Also the blueprint onboarding screens not in the build prompt's 11 steps (goals, medications, health considerations, mascot picker). Clinical interaction rules ship `enabled: false`.
