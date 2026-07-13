# WakeGuard — Final Release Audit (session kickoff prompt)

> Paste this whole file as the first message of a fresh session. It is self-contained: assume you
> (the auditing agent) have **no prior context**. Your job is a comprehensive, release-gating audit of the
> entire WakeGuard product — Flutter app **and** Arduino firmware — and a prioritized report. **Audit and
> report; do not change code unless explicitly asked in a follow-up.**

---

## 1. What WakeGuard is

A smart alarm clock for people who struggle to wake up (narcolepsy / sleep inertia). Two halves that speak a
hand-rolled binary BLE protocol:

- **Flutter app** — `smart_ble_alarm/` (Dart, BLoC/Cubit, feature-based `lib/features/…` layout). Pairs with
  the clock, configures alarms, and can run standalone (Phone Alarm companion / Dedicated Clock). Uses
  Firebase (auth/account/profile/cloud alarm backup), Google ML Kit (on-device image labeling for the
  photo wake-challenge), local notifications (backup alarms), and a "Liquid Glass" design system.
- **Arduino firmware** — `arduino/WakeGuardClock/` (C++). Autonomous: keeps time (no RTC; software drift
  calibration), persists to EEPROM, rings on schedule with no phone present, and enforces dismissal tokens
  in hardware.
- **Differentiator**: task-gated dismissal — silencing an alarm requires a real-world action (photograph a
  chosen object, verified on-device; or scan a printed QR backup code). No free "dismiss anyway".

Release target: **iOS App Store / TestFlight** (bundle `com.mekylealam.wakeguardalarm`), Android secondary.

## 2. Repo map

- `smart_ble_alarm/lib/` — app source. Core: `core/ble/` (framing, payloads, `clock_sync.dart`),
  `core/theme/` (`glass.dart`, `wake_widgets.dart`, `app_theme.dart`), `core/notifications/`,
  `core/challenge/`. Features under `lib/features/**` (alarms, bluetooth, onboarding, account, display,
  settings, home, dedicated_clock, wake_challenge, timers, history). App shell: `lib/app/`, `lib/main.dart`.
- `smart_ble_alarm/test/` and `smart_ble_alarm/integration_test/` — automated tests.
- `arduino/WakeGuardClock/` — firmware (keep byte-for-byte in sync with the Dart BLE side).
- `agent reference/` — prior audit docs: **read `Production Pre-Release Audit Spec.md`,
  `Pre-Release Blockers — Shortlist.md`, and `Pre-Release Audit — Task 1 BLE Wire Protocol.md` first** and
  reconcile your findings with them (confirm each prior blocker is actually resolved in the current tree).
- Firebase config: `firebase.json`, `firestore.rules`, `storage.rules`, `.firebaserc`,
  `smart_ble_alarm/lib/firebase_options.dart`, `android/app/google-services.json`,
  `ios/Runner/GoogleService-Info.plist`.
- `PROJECT_LOG.md` / `README.md` — product + contribution record (treat as claims to verify, not ground truth).

## 3. Current-state caveats you MUST know before auditing

1. **A large refactor recently landed** (feature-based `lib/features/**`, Firebase/account/analytics/crash
   reporting added). Watch for refactor fallout: orphaned/dead code from the old `lib/presentation/**`
   layout, broken/duplicate imports, dead providers, and screens wired to nothing.
2. **Privacy regression risk (flag explicitly).** A prior commit deliberately removed location permissions
   and the geolocation weather feature ("so the app does not collect data"); the current tree **re-adds**
   `ACCESS_FINE/COARSE_LOCATION`, the iOS `NSLocation…UsageDescription` strings, and ipapi.co+Open-Meteo
   geolocation weather. Verify whether that is intended for release, and whether the **iOS Privacy Manifest**
   (`ios/Runner/PrivacyInfo.xcprivacy`) and App Store privacy "nutrition labels" match what the app actually
   collects (location, analytics, crash data, account/profile, alarms).
3. **Secrets & Firebase security.** Confirm `firestore.rules` / `storage.rules` are **locked to
   authenticated owners** (not left in test-mode `allow read, write: if true`). Decide whether committing
   `google-services.json` / `GoogleService-Info.plist` / `firebase_options.dart` is acceptable (these are
   client config, but flag any real private keys, service-account JSON, or API keys with excess scope).
4. **BLE contract is fixed and length-guarded.** The `0x02` alarm frame and the command set are a coordinated
   app+firmware contract; any change must be made on both sides + reflected in `syncHash`. Verify the Dart
   encoder and the C++ decoder still agree byte-for-byte.
5. **ML Kit iOS simulator build** historically fails to link on arm64 (MLImage); the fix is excluding arm64
   for the simulator (x86_64 under Rosetta) in the xcconfigs + Podfile. Confirm device builds are unaffected.
6. **A GateGuard hook is active**: you must present a short "facts" block before the first Bash command, before
   edits, and before destructive/git commands. This is expected — comply and proceed; don't fight it.
7. The working tree may contain uncommitted attribution docs (`CONTRIBUTORS.md`, `AARON_UPDATE_LOG.md`, edits
   to `*_UPDATE_LOG.md`). Ignore these for the code audit.

## 4. Audit dimensions (cover all; go deep where risk is highest)

For each finding give: **severity** (Blocker / High / Medium / Low), file:line, concrete failure scenario,
and a recommended fix. Separate **release Blockers** from advisory items.

1. **Build & tooling** — `flutter analyze` is clean; `flutter test` + integration tests pass; iOS **device**
   build and Android release build succeed; no analyzer ignores hiding real issues.
2. **Security & privacy** — Firestore/Storage rules; secret/key exposure; the HMAC-SHA256 backup-token and
   dismissal-token handling; auth flows (Google/Apple sign-in); privacy manifest + data-collection labels;
   permission justifications; the location/weather regression above.
3. **BLE protocol correctness** — framing/escape/checksum, 20-byte MTU chunking, the write mutex, the ring
   handshake (`0x08`/`0x88`/`0x89`), length-guarded `0x02` evolution, and Dart↔C++ byte-for-byte agreement.
4. **Alarm reliability** — scheduling/next-occurrence + DST, the real `0x09` dismissal path, snooze/volume/
   gradual-wake bytes, 5-slot enforcement, storage-envelope migration, and the notification backup layer.
5. **Firebase / cloud** — account lifecycle, profile + cloud alarm backup/restore correctness and conflict
   handling, offline behavior, and failure/error surfacing (no silent swallow).
6. **State management & correctness** — BLoC event ordering (the sequential AlarmBloc transformer), sync
   coalescing, race conditions, disposal/leaks, and silent failures / swallowed exceptions.
7. **Refactor hygiene** — dead code from the `lib/presentation`→`lib/features` move, unused files/providers,
   duplicated logic, and stale references.
8. **Accessibility** — Dynamic Type growth without clipping, ≥44pt hit targets, contrast in light+dark,
   semantics/labels, reduced-motion. (Prior work established these — verify they survived the refactor.)
9. **Performance** — startup time, unnecessary rebuilds, blur/`BackdropFilter` cost, image/label pipeline.
10. **App Store readiness** — Info.plist usage strings, export compliance (HMAC-only → exempt, confirm),
    bundle id/versioning, launch screen, and rejection risks (e.g., ITMS-90683-class missing purpose strings).
11. **Docs accuracy** — README/PROJECT_LOG claims (test counts, features, protocol) match the code.

## 5. Method

- Start by reading the prior audit docs in `agent reference/` and confirming each listed blocker's current
  status in-tree (don't trust "resolved" — verify).
- Run `flutter analyze` and the test suites early to get a factual baseline.
- **Fan out with specialized subagents in parallel** where useful: e.g. the `flutter-reviewer` /
  `security-reviewer` / `silent-failure-hunter` / `code-reviewer` agents, and skills like `ecc:flutter-review`,
  `ecc:security-review`, `ecc:production-audit`. Give each a tight scope from §4 and have it return
  structured findings; you synthesize and de-duplicate.
- **Adversarially verify** every Blocker/High finding before reporting it (reproduce the failure path in the
  code; don't report plausible-but-unconfirmed issues as blockers).
- Keep BLE findings grounded by diffing the Dart payloads against the C++ decoder directly.

## 6. Deliverable

Produce a single markdown report (suggest `agent reference/Final Release Audit — Report.md`) with:
- **Release verdict**: Ship / Ship-with-fixes / Do-not-ship, one line.
- **Blockers** (must fix before release) — ranked, each with file:line + failure scenario + fix.
- **High / Medium / Low** advisory findings, grouped by dimension.
- **Reconciliation** with the prior `agent reference/` audit docs (what's now truly resolved vs still open).
- **Privacy & data-collection summary** (what the app collects, whether labels/manifest match, the location
  question).
- A short **"green checklist"** of what passed, so the record shows coverage, not just problems.

Do not commit, push, or modify code as part of the audit unless a follow-up explicitly asks. Report first.
