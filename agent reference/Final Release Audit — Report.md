# WakeGuard — Final Release Audit — Report

> Scope: full-product release-gating audit of the Flutter app (`smart_ble_alarm/`) **and** Arduino
> firmware (`arduino/WakeGuardClock/`), per `Final Release Audit Prompt.md`.
> Method: factual build/test baseline + direct read of high-risk surfaces, then a parallel fan-out of 8
> specialized subagents (BLE↔firmware, alarm reliability, Firebase/cloud, Flutter quality, security/privacy,
> silent-failure, refactor hygiene, accessibility). **Every Blocker/High below was adversarially
> re-verified against the code by the lead auditor** (file:line cited). Audit-and-report only — no code
> was modified.
> Date: 2026-07-13 · Branch: `main` · Version: `0.1.0+1` · Target: iOS App Store / TestFlight (Android secondary).

---

## 1. Release verdict

**SHIP-WITH-FIXES (iOS)** — the iOS app is close (analyzer clean, 53 tests pass, App Store readiness largely met,
no wake-challenge bypass in software), but **two silent data-loss Blockers in the account/cloud layer (B1, B2)
must be fixed first**. **DO-NOT-SHIP (Android)** until the build is fixed — the Android build is currently broken
and the release is debug-signed (B3).

---

## 2. Baseline (facts)

| Check | Result |
|---|---|
| `flutter analyze` | ✅ **Clean — "No issues found!"** (no analyzer ignores hiding issues found) |
| `flutter test` | ✅ **53 tests pass** (docs claim 39 — stale; see D-3) |
| iOS device build (`flutter build ios --no-codesign`) | ⚠️ **Unverified in this environment** — Dart compiled; `pod install` failed on a local CocoaPods/specs-repo version mismatch (1.16.2 vs lockfile 1.17.0). Environmental, **not** a code defect. Re-run on a machine with matching CocoaPods. |
| Android build (`flutter build apk`) | ❌ **Fails** — see **B3**. |
| ML Kit arm64-simulator exclusion (prior caveat) | ✅ Correctly configured in `ios/Podfile` + `Debug/Release/Generated.xcconfig`; device builds keep arm64. |

---

## 3. Release Blockers (must fix)

### B1 — Signing in on a fresh device SILENTLY WIPES the user's cloud alarm backups
**Severity: Blocker · Dimension: Firebase/cloud · Data loss**

- **Path (verified):** `lib/app/smart_alarm_app.dart:206-212` → `lib/features/alarms/presentation/bloc/alarm_bloc.dart:295-300` → `lib/features/alarms/data/alarm_cloud_sync_service.dart:51-68`.
- On sign-in the `BlocListener` fires `SyncAlarmBackupsEvent` (a **push**, not a restore) the instant `uid` becomes non-null. `_onSyncAlarmBackups` calls `alarmCloudSyncService.syncAlarms(state.alarms)`. On a fresh install/new phone, `_onLoadAlarms` has loaded an **empty** local set (and, correctly, does not auto-restore cloud). `syncAlarms([])` computes `currentIds = {}` and its delete loop (`:64-68`) deletes **every** existing `alarmBackups` doc, then writes `alarmBackupCount: 0`.
- **Failure scenario:** User backs up on Phone A, installs on Phone B, signs in to *restore* → their entire cloud backup is deleted before they can restore it. Settings → Restore then shows "No cloud alarm backups were found." Total, silent loss. Directly defeats the advertised backup/restore feature.
- **Fix:** Do not auto-push on sign-in. On sign-in, restore-then-merge (a safe `restoreIfLocalEmpty` already exists at `alarm_cloud_sync_service.dart:19-22` but is unused on this path). At minimum, guard `syncAlarms` so an empty (or strictly smaller) local set never deletes a non-empty cloud backup, and prompt the user to restore on a fresh device before any push.

### B2 — Account deletion destroys cloud data BEFORE the auth account, with no re-authentication
**Severity: Blocker · Dimension: Firebase/cloud + App Store · Data loss + Apple 5.1.1(v)**

- **Path (verified):** `lib/features/account/presentation/cubit/account_cubit.dart:417-446`. Order is `await _deleteCloudAccountData(user.uid)` (`:427`, deletes Storage avatar + Firestore user doc + `alarmBackups` subcollection, `:522-548`) **then** `await user.delete()` (`:428`). No `reauthenticateWithCredential` exists anywhere in the codebase.
- **Failure scenario:** Firebase requires a *recent* login for `User.delete()`. The common case (a persisted session older than a few minutes) throws `requires-recent-login` — but only **after** all cloud data has already been irreversibly deleted. Result: Firestore/Storage data gone, auth account still exists, user shown "sign in again before deleting." Both a data-integrity bug and an App Store account-deletion-completeness risk (guideline 5.1.1(v)).
- **Fix:** Re-authenticate (or verify recent login) *first*; only on success delete cloud data, and delete the auth user **last**. On `requires-recent-login`, abort **before** touching cloud data and route the user through reauth.

### B3 — Android build is broken, and the release build is debug-signed
**Severity: Blocker (Android only — iOS unaffected) · Dimension: Build & tooling**

- **B3a (verified):** `pubspec.yaml:87` declares `default-flavor: WakeGuard`, so Flutter invokes `assembleWakeGuard<BuildType>`, but `android/app/build.gradle.kts` defines **no product flavors**. Every Android build (`flutter build apk`/`appbundle`, `flutter run`) fails with *"Gradle project does not define a task suitable… does not define any custom product flavors."* iOS is fine — it has a matching `ios/Runner.xcodeproj/…/xcschemes/WakeGuard.xcscheme`.
  - **Fix:** add a matching `productFlavors { create("WakeGuard") { dimension = "default" } }` (+ `flavorDimensions`) to the Android Gradle config, or remove `default-flavor` from pubspec and manage the iOS scheme another way.
- **B3b (verified):** `android/app/build.gradle.kts` release `signingConfig = signingConfigs.getByName("debug")` — the release build is signed with the **debug** keystore and cannot be uploaded to Play. Also `applicationId = "com.smartblealarm.smart_ble_alarm"` (iOS bundle is `com.mekylealam.wakeguardalarm.a74sa4d686b`) — cross-platform id divergence.
  - **Fix:** add a real release signing config before any Android release; align/confirm the applicationId.

> **Note on the firmware wake-challenge hole (A-a below):** it is on the product's core differentiator and
> the prior Shortlist rated it 🔴. It is ranked **High** here (not Blocker) because it is firmware (not the
> TestFlight artifact), its reachability is conditional, and the app never emits a bad token for a secured
> alarm in normal flow. **If the team treats the tamper-proof guarantee as release-gating, promote it to Blocker.**

---

## 4. High-severity findings (grouped by dimension)

### Security / BLE
- **A-a · Firmware `tryDismiss` accepts ANY token on a secured-but-tokenless slot.**
  `arduino/WakeGuardClock/WakeGuardClock.ino:951-957` — the `else` branch (`:956 ok = true`) dismisses a
  `qrRequired` alarm that has no stored token (including the all-zero unsecured frame). **Reachable** when
  `0x02` (add, `qrRequired=1`) lands but the separate `0x07` token push is dropped/lost (fire-and-forget,
  no ACK checking — see A-b), leaving a secured slot with `hasToken==0`. The app itself never sends a bad
  token for a secured alarm, so real-world exposure is an attacker in BLE range (small 0–4 id space) or
  corruption — but it silently defeats the hardware-enforced "no free dismiss" promise. The backup token is
  actually *static*, so the "don't strand the user" justification for the bypass is weak once a token is stored.
  **Fix (coordinated app+firmware):** in the no-token branch set `ok=false` and keep ringing; have the
  firmware re-request the `0x07` token rather than granting dismissal.

- **A-b · App never consumes ACK / `0xFF CMD_ERROR`; "Synced" means "wrote to the radio," not "clock accepted it."**
  `lib/data/repositories/ble_repository_impl.dart:140-174` (`sendCommand` resolves on local GATT write) +
  `lib/app/navigation/main_screen.dart:151-174` (inbound handler branches only on `0x08`/`0x89`). The firmware
  emits real ACKs (`0x81–0x8D`) and `0xFF` with sub-codes (`ERR_CHECKSUM`/`ERR_TOO_LONG`/`ERR_INVALID_CMD`,
  `.ino:742/750/797`) that the app discards. `AlarmSyncStatus.synced` (`alarm_bloc.dart:438-448,572`) is set
  purely from the local write not throwing → an alarm can read **"Synced" while the clock rejected the frame**.
  *Impact High, likelihood low* (write-with-response + BLE link-layer 24-bit CRC make app-frame corruption
  rare). This is also the umbrella reason A-a's lost-token state is never surfaced.
  **Fix:** handle inbound `0xFF`/ACKs; confirm `syncedHashes` only on the matching ACK (with timeout).

### Alarm reliability
- **AR-1 · Restore path has no 5-slot cap → >5 alarms silently under-served.**
  `alarm_bloc.dart:315-320` (`_onRestoreAlarmBackups` merges cloud+local with no cap); `_onSyncAlarmsToDevice`
  then `.take(maxHardwareAlarms)` (`:562-565`) so alarms beyond the lowest-5 are **never written** to the
  clock and sit at `pending` forever with no explanation. The direct edit-write path (`:388-389,432-435`) also
  ignores the cap. **Fix:** cap the merged list on restore, surface "N alarms can't fit the clock's 5 slots,"
  and make the direct-write path respect the same lowest-5 selection.

### Correctness / App Store honesty
- **C-1 · "Phone Alarm (Beta)" toggle is inert, and its Android copy is a false safety claim.**
  `lib/features/settings/presentation/screens/settings_screen.dart:1087-1143` renders "Ring on this phone" /
  "Only while charging," but `phoneAlarmEnabled`/`phoneAlarmRequireCharging` are consumed **nowhere** (grep:
  only the settings bloc/screen), there is **no** battery/charging detection, and `MainActivity.kt` is a stock
  `FlutterActivity`. The footnote (`:1120-1125`) states *"On Android this rings full-screen and can only be
  silenced by your wake challenge"* — that behavior does not exist. (The iOS sentence is honestly hedged.)
  *Mitigated:* the independent backup-notification layer still rings for enabled alarms (gated by a **different**
  toggle), and the feature is Beta/off-by-default. **Fix:** implement the engine, or remove the section /
  correct the Android copy and wire the flag to real behavior. Do not ship the false Android claim.

### Accessibility (advisory — strongly grounded by the a11y pass; not independently re-derived)
- **AX-1 · Bare `GestureDetector` controls invisible to VoiceOver/TalkBack.** Notably the **whole alarm card**
  (`alarms_tab.dart:338`) — the only way to open the editor for any non-"next" alarm → screen-reader users
  effectively can't edit alarms. Also `home_tab.dart:1051`, `settings_screen.dart:833,898`,
  `alarm_edit_screen.dart:821,1228`. Correct pattern already exists (`alarm_edit_screen.dart:763-767`
  `_dayChip`). **Fix:** wrap each in `Semantics(button:true, selected:, label:)`.
- **AX-2 · Hardcoded `Colors.white` on accent thumbs → ~2:1 contrast.** `alarms_tab.dart:174`,
  `alarm_edit_screen.dart:1244` bypass the theme's luminance-derived on-accent color (`app_theme.dart:48-51`);
  white-on-Mint ≈ **2.02:1** (fails 4.5:1). **Fix:** derive label color via `estimateBrightnessForColor(primary)`.
- **AX-3 · Semantic status colors used as text fall below 4.5:1 in light theme.** `WakeStatusPill`
  (`wake_widgets.dart:317-359`) paints text in the raw semantic color over a 12% tint; warning ≈1.83:1,
  success ≈2.22:1, error ≈3.41:1 vs light glass. Systemic across Offline/Pending/Failed/Backup-off pills.
  **Fix:** in light theme use `onSurface`/darkened variants for text, reserving saturated color for icon/wash.

---

## 5. Medium-severity findings (grouped by dimension)

### State management / correctness
- **M-1 · Awaiting an offline Firestore commit inside a serialized handler.** `_onSyncAlarmBackups`
  (`alarm_bloc.dart:295-300`, `_sequential()` transformer `:240,250`) awaits `batch.commit()`
  (`alarm_cloud_sync_service.dart:87`), whose Future **does not resolve while offline**. *Calibration:* bloc
  applies transformers per-event-type, so this stalls only subsequent `SyncAlarmBackupsEvent`s, **not** add/
  edit/delete/ring events — the subagent's "freezes the whole AlarmBloc" is overstated. Still, sign-in while
  offline leaves a hung handler holding an open commit. **Fix:** fire-and-forget (`unawaited`, as `_syncCloudBackups`
  at `:663` already does) or bound with a timeout.
- **M-2 · A single malformed stored alarm drops the entire list.** `parseStoredAlarms` (`alarm_bloc.dart:639-653`)
  maps every entry through `Alarm.fromJson` (unguarded casts, `alarm.dart:211`); one bad record throws, the
  `catch (_)` in `_onLoadAlarms` (`:262-264`) yields an empty set, and a later save persists the empty list.
  **Fix:** parse per-entry, skipping only the bad record.

### Firebase / cloud & error surfacing
- **M-3 · Cloud-restore failures are indistinguishable from "no backups."** `restoreBackups`
  (`alarm_cloud_sync_service.dart:24-49`) catches all errors and returns the empty fallback, so
  `_onRestoreAlarmBackups` reports `0` (not an error) and the user always sees "No cloud alarm backups were
  found" — even on a transient network/permission error where backups exist. Compounds B1. **Fix:** distinguish
  empty-result from error; surface offline/permission distinctly.
- **M-4 · Background backup-sync failures are invisible** (`alarm_cloud_sync_service.dart:88-97` — only
  `debugPrint` + Crashlytics). User keeps believing alarms are backed up. **Fix:** track last-successful-backup
  and surface a "backup failing" indicator.
- **M-5 · Google `serverClientId` uses the Android client id; on iOS it resolves to null** (`account_cubit.dart:550-560`
  vs `firebase_options.dart`). Can break Google ID-token issuance/acceptance. Functionality risk, not auth-bypass.
  **Fix:** verify "Continue with Google" on real iOS + Android; wire the web/server client id if needed.
- **M-6 · Crash/error handlers never wired when Firebase isn't ready, and never retried.**
  `crash_reporting_service.dart:17-19` returns early if `_client == null`; `main.dart` calls `initialize()` once.
  Since the app runs fully in local mode (no sign-in), a large share of sessions get **zero** global crash
  capture (`FlutterError.onError`/`PlatformDispatcher.onError` never set). Observability-only (not user-facing).
  **Fix:** register handlers unconditionally at startup; check `AppFirebase.isReady` at error time.

### Alarm reliability
- **M-7 · Timezone fallback drops fractional offsets to UTC.** `notification_service.dart:91-104` only maps
  whole-hour offsets; India (+5:30), Nepal, Newfoundland, parts of Australia stay at the UTC default →
  backups fire hours off. Fallback path only (primary IANA lookup usually succeeds). **Fix:** handle 30/45-min
  offsets. *(Partial regression of the prior "TZ fallback" fix, which covered only whole hours.)*
- **M-8 · Dedicated Clock: two alarms in the same minute → only the first rings** (`dedicated_clock_screen.dart:108-126`);
  if the first is dismissed after the minute rolls over, the second never fires. **Fix:** queue/re-scan coincident alarms.
- **M-9 · One-time alarm re-arms its backup / re-fires when dismissal isn't observed.** A one-time alarm is
  cleared only when the app sees the ring stop (`0x89` over a live BLE link, or Dedicated Clock dismissal). With
  on-demand BLE the phone is usually disconnected when the hardware rings, so `isActive` stays set and the next
  app open reschedules a backup / re-fires. **Fix:** reconcile last-fired one-time id on reconnect, or expire
  past-due one-time backups on load instead of rolling forward.
- **M-10 · Notification init failure / permission denial not surfaced.** `notification_service.dart` init failure
  is only `debugPrint`ed (`smart_alarm_app.dart:317-325`), and `requestNotificationsPermission`/
  `requestExactAlarmsPermission` results are discarded (`:68-73`) while `_ready=true` regardless → the backup
  safety net can be silently off while the Settings toggle shows "on." **Fix:** route init failure to Crashlytics;
  capture + surface OS permission state.

### BLE robustness
- **M-11 · No ring-state resync on reconnect.** After the app ACKs (`0x88`), the clock stops re-broadcasting
  `0x08` (`.ino:894-896,1021`). If the phone disconnects during a continuous ring of a **secured** alarm, on
  reconnect the ringing UI never reappears (no "query ring state" command) and the physical button only
  *snoozes* secured alarms — the user may be unable to silence it from the app. **Fix:** re-broadcast `0x08` on
  any new GATT connection while `ringLatched`, or add a ring-state query.
- **M-12 · `_onSyncAlarmsToDevice` aborts the whole batch on the first delete failure**
  (`alarm_bloc.dart:538-556`): remaining deletes and the entire upsert loop are skipped, and successful deletes
  aren't persisted. Self-healing (retries next sync). **Fix:** `continue` past a failed delete; report partial failure.
- **M-13 · False-success on no-task dismiss.** `ringing_dismissal.dart:110-124` (`_dismissNoTask`) swallows the
  `0x09` write error and still clears the ring + shows green "Alarm dismissed." The comment claims the clock
  "self-silences on its button," but the buzzer has **no auto-timeout**. Recoverable via the physical button
  (only unsecured alarms reach this path). Sibling screens (`scanner_screen.dart:84-105`,
  `item_scan_screen.dart:153-181`) do it right. **Fix:** on write failure keep ringing + show an error.

### Security / privacy
- **M-14 · Storage write rule accepts `image/svg+xml`.** `storage.rules:10` uses `contentType.matches('image/.*')`.
  A throwaway account (no email verification) can upload an SVG with `<script>` to its own profile path and share
  the permanent download URL; opened directly in a browser it executes in the storage origin. **Fix:** restrict to a
  raster allow-list (`in ['image/jpeg','image/png','image/webp','image/heic','image/heif']`).
- **M-15 · Storage `read` is not owner-scoped.** `storage.rules:6` `allow read: if request.auth != null` → any
  authenticated user can read any user's `profile/*`. Confirm intended; if not, scope to the owner.
- **M-16 · In-app privacy dialog omits the weather/IP disclosure.** `settings_screen.dart:1359-1391` covers camera/
  BLE/Firebase/deletion but never mentions that the weather feature sends the user's IP to **ipapi.co** and the
  derived lat/lon to **open-meteo.com**. The repo `Privacy Policy.md` §5 does disclose it, but that isn't shipped.
  **Fix:** add the weather/location paragraph to the in-app dialog; list ipapi.co + Open-Meteo as recipients in the
  App Store/Play privacy questionnaires.

### App Store / privacy config
- **M-17 · Android location permissions look vestigial.** `AndroidManifest.xml:3` flags `BLUETOOTH_SCAN`
  `neverForLocation`, weather is IP-based (no GPS), yet `ACCESS_FINE/COARSE_LOCATION` are declared (`:5-6`) and
  `Permission.locationWhenInUse` is requested on Android (`setup_screen.dart:104-105`). Only justified by legacy
  BLE scanning on Android ≤11. **Fix:** if minSdk ≥ 31, remove them; otherwise document the legacy-BLE justification
  and reflect location in the Play Data Safety form. (iOS never requests CoreLocation — see §7.)

### Docs accuracy
- **D-1 · README describes the removed layout + wrong protocol.** `README.md:22,46-65` link/describe
  `lib/presentation/**` (deleted) and the old tree; the `0x06` row (`:91`) still says
  `[autoDim, sleepStartH…]` — current `0x06` is `[flags, theme, accent]` and sleep is a separate `0x0D`; `0x0C`
  weather and `0x0D` display-sleep are missing from the table. **Fix:** update paths + protocol table.
- **D-2 · `PROJECT_LOG.md:172`** describes `0x06` as "auto-dim via light sensor, plus sleep-mode start/end" — a
  removed feature. **Fix:** update to the current `0x06`/`0x0D` semantics.
- **D-3 · `CLAUDE.md:143`** claims "39 tests currently pass"; the suite now runs **53**. **Fix:** update the count.

---

## 6. Low-severity findings

- **BLE-L1 · XOR-only checksum (no CRC).** `ble_framing.dart:13-16` / `.ino:685-686`; can't catch transpositions/
  even-count bit flips, symmetric on both sides. Mitigated by BLE link-layer CRC + acked writes. Optional: CRC-8 in a
  coordinated, version-bumped change.
- **BLE-L2 · Item-scan 3-min backup gate keys on `ringingSince` and hides when `ringingAlarmId != alarm.id`**
  (`item_scan_screen.dart:188-197`). Works in the normal flow; the gate restarts on a mid-ring reconnect. **Fix:**
  fall back to unlock (rather than hide) when ring-start is unknown.
- **BLE-L3 · Corrupted inbound frames dropped with no log** (`ble_framing.dart:100-128`); **BLE-L4 · BLE connect/scan
  failures discarded with no telemetry** (`ble_bloc.dart:67-70,101-106,135-140,175-183`). Add a breadcrumb/analytics event.
- **SEC-L1 · Item-scan is an honor-system check** (`image_recognition_datasource.dart:44-49`, threshold 0.6) — no
  liveness; a photo-of-a-photo or a generic label passes. Consistent with the product's "get the user up" goal.
  **SEC-L2 · 3-min gate is wall-clock** (device-clock tamperable). Both acceptable for the stated threat model; document.
- **OBS-L1 · Observability not consent-gated; every framework error reported `fatal:true`** (`crash_reporting_service.dart:20-27`)
  inflates the crash-free metric. No PII logged (UID only). Consider non-fatal for framework errors + a consent/debug gate.
- **REL-L1 · Backup notifications ignore volume/gradual-wake/snooze** (`notification_service.dart:264-299`) — documented
  limitation; state it for QA. **REL-L2 · Fallback fixed-offset zone doesn't track DST** across a long-lived process (rare).
- **CODE-L1 · Dead widgets** `WakeMetricTile` + `WakeQuickAction` (`wake_widgets.dart:362,420`) — zero references; delete.
  **CODE-L2 · `showAppSnackBar` not adopted everywhere** (many direct `ScaffoldMessenger` calls) — optional consistency.
  **CODE-L3 · No `ErrorWidget.builder`** for release (grey box on build errors). **CODE-L4 · `AccountCubit._canUseAuth`
  is a getter that `emit`s** (`account_cubit.dart:448-458`) — make it a method. **CODE-L5 · unwrapped `SharedPreferences`
  writes** in `_onAddOrUpdateAlarm`/`_onDeleteAlarm` can short-circuit the handler (rare).
- **AS-L1 · Build number `+1`** — must bump on every TestFlight upload. **AS-L2 · Runner has no explicit
  `CODE_SIGN_STYLE`** (submitter sets distribution signing). **AS-L3 · Firebase project id spelled `wakegaurd`**
  (`.firebaserc`, `firebase_options.dart`) — internally consistent; confirm it matches the real project.
- **AX-L (accessibility) ·** Reduce-Motion only wired to the ambient background (M-class control animations use a
  separate in-app toggle); several fixed-height containers + fixed-width numeric readouts + the `CupertinoPicker`
  clip at large Dynamic Type; toggle rows don't `MergeSemantics` label+Switch; avatar button unlabeled; ringing state
  not a `liveRegion`; QR/photo challenge has no non-visual fallback. See the a11y pass §MEDIUM/§LOW for the full list
  with file:line — all advisory, none block a core flow except AX-1.

---

## 7. Privacy & data-collection summary

**What the app collects / transmits**
- **Account (only if the user signs in):** email, display name, optional profile photo, Firebase UID → **Firebase**
  (Auth/Firestore/Storage). Cloud alarm backups (alarm config) → Firestore.
- **Analytics:** onboarding/sync events with **non-PII** params + UID → **Firebase Analytics**.
- **Crash data + UID** → **Firebase Crashlytics**.
- **Approximate location (weather feature only):** phone IP → **ipapi.co** (IP→lat/lon), lat/lon → **open-meteo.com**
  (weather). No device GPS. No `geolocator` dependency.
- **Camera images (wake challenge):** processed **on-device** (ML Kit / QR); not stored or transmitted. ✅ verified.
- **No PII in Crashlytics/Analytics** beyond the Firebase UID. ✅ verified. **No secrets committed** (only public
  Firebase client config). ✅ verified.

**iOS Privacy Manifest (`ios/Runner/PrivacyInfo.xcprivacy`) — now populated** and broadly matches actual collection:
declares Name, Email, UserID (+Analytics), Photos/VideoData, OtherUserContent, ProductInteraction (Analytics),
CrashData, and **CoarseLocation** (AppFunctionality, not linked, not tracking). `NSPrivacyTracking=false`, no tracking
domains, `UserDefaults` reason `CA92.1`. This is a solid, defensible manifest.

**The location question (resolved):**
- **iOS never requests CoreLocation** — location permission is requested **only on Android** (`setup_screen.dart:104`).
  The iOS `NSLocation…UsageDescription` strings exist to satisfy a bundled-SDK static requirement (prior ITMS-90683),
  not active use. Declaring `CoarseLocation` (IP-derived) in the manifest is the conservative, correct choice.
- **Android** requests `locationWhenInUse` and declares `ACCESS_FINE/COARSE_LOCATION`, but with
  `BLUETOOTH_SCAN … neverForLocation` and IP-based weather, these are effectively **legacy-BLE-only** (Android ≤11)
  and otherwise vestigial → **M-17**.

**Gap:** the *shipped* in-app privacy dialog omits the ipapi.co/Open-Meteo disclosure that the repo policy makes → **M-16**.
Ensure the App Store/Play privacy questionnaires list ipapi.co + Open-Meteo as recipients of approximate location.

---

## 8. Reconciliation with prior `agent reference/` audit docs

**`Audit 1 report.md`** — all 6 historical findings remain **resolved** (4-byte epoch time sync, alarm persistence,
real `0x09` dismissal, timer quick action, dev section removed, 5-byte→current settings frame kept by design). ✅

**`Pre-Release Audit — Task 1 BLE Wire Protocol.md`** — verdict holds: app↔firmware **agree byte-for-byte** on framing,
checksum, the 9-byte `0x02` layout, the length-guarded extension rule, and all 13 commands + the `0x08/0x88/0x89` ring
handshake (independently re-verified). Its residual leads are still open: XOR-only checksum (BLE-L1), app ignores `0xFF`
(A-b), `id` throw-vs-mask asymmetry (latent), local-epoch convention (by design). ✅ + residuals tracked.

**`Pre-Release Blockers — Shortlist.md`:**

| Item | Prior status | Now |
|---|---|---|
| Privacy manifest present | ✅ created | ✅ created **and now fully populated** (better than at Shortlist time) |
| `audioplayers`/`wakelock_plus` in Podfile.lock | ✅ n/a | ✅ confirmed present |
| `ITSAppUsesNonExemptEncryption=false` | ✅ added | ✅ present (`Info.plist:40-41`) |
| Notification TZ fallback (whole-hour) | ✅ fixed | ✅ whole-hour correct; **fractional offsets still fall to UTC (M-7)** |
| AlarmBloc handler signatures `Future<void>` | ✅ hardened | ✅ confirmed |
| Runner `CODE_SIGN_STYLE` | ⬜ submitter | ⬜ still implicit (AS-L2) |
| `UIBackgroundModes` vs foreground ring | ⬜ scope | n/a for iOS (ring is foreground; Phone Alarm is inert anyway, C-1) |
| Android debug-signing + applicationId | 🟡 if Android ships | ❌ **now a hard build break + debug-signed (B3)** |
| `build/…workspace-state.json` tracked | ✅ untracked (staged) | git hygiene OK (`/build/` ignored) |
| **Firmware `tryDismiss` no-token accept** | ⏳ needs decision | **STILL OPEN (A-a)** |
| XOR checksum + app ignores `0xFF` | ⬜ | **STILL OPEN (A-b / BLE-L1)** |
| `_onSyncAlarmsToDevice` early-return on delete fail | ⬜ | **STILL OPEN (M-12)** |
| item_scan 3-min gate | ⬜ | **STILL OPEN (BLE-L2)** |
| Dedicated Clock one-time re-fire / same-minute | 🟡 if DC ships | same-minute **STILL OPEN (M-8)**; one-time handled on *observed* dismissal (M-9) |
| Global static token + no-op `deleteKey` | not-a-bug | confirmed by design (no bypass found) |

**New since the prior docs** (from the Firebase/account layer added in the refactor): **B1, B2, M-3/M-4/M-5/M-6, C-1**.

---

## 9. Green checklist (what passed)

- ✅ `flutter analyze` clean; **53** unit/widget tests pass (incl. BLE framing/payloads, syncHash, storage-envelope
  migration v1→v2, no-auto-restore-on-load).
- ✅ **BLE app↔firmware byte-for-byte agreement** on framing, XOR checksum, 15-byte cap, 20-byte MTU chunking + write
  mutex, the 9-byte `0x02` layout, and all 13 commands; `0x08/0x88/0x89` ring handshake correct on both sides.
- ✅ **Wake-challenge software path is sound — no bypass.** HMAC-SHA256 over a 128-bit `Random.secure()` key in
  `flutter_secure_storage` (Keychain/Keystore), constant-time compare, only the derived 8-byte token crosses BLE, and
  the zero-token dismiss path is reachable **only** for unsecured alarms. (The one hole is firmware-side: A-a.)
- ✅ **Firestore rules** lock `/users/{uid}/**` to the owner. **No secrets/keys committed** (only public Firebase client config).
- ✅ **Apple Sign-In nonce** implemented per Firebase's replay-resistant pattern (raw + SHA-256). Sign-out clears Firebase + Google SDK.
- ✅ **App Store readiness:** purpose strings present; `ITSAppUsesNonExemptEncryption=false`; **populated** privacy
  manifest; **ML Kit arm64-simulator exclusion correct** (device builds keep arm64); LaunchScreen present; bundle id/team set.
- ✅ **Refactor is clean:** `lib/presentation/**` fully removed; no orphaned files (56/56 reachable), no duplicate
  screens/blocs, no stale old-path imports, no leftover placeholders; the one declared asset is used.
- ✅ **Alarm scheduling fundamentals:** day-mask↔weekday mapping off-by-one-free across all four sites; Android reboot/
  exact-alarm persistence configured; `syncAlarms` cancels-all before rescheduling; storage v1→v2 migration is loss-free;
  snooze/volume/gradual-wake consistent app→wire.
- ✅ **Lifecycle/leaks:** blocs/cubits, timers, animation controllers, stream subscriptions, and `ValueNotifier`s dispose
  correctly; async-gap `mounted`/`context.mounted` checks in the wake-challenge + delete flows.
- ✅ **Reduced motion** honored by the animated backgrounds; **dark-theme contrast** ≥8:1; the prior "white text in light
  mode" concern does **not** reproduce in the current theme.
- ✅ Firebase init **degrades gracefully to local mode**; auth errors mapped to friendly messages; no PII in telemetry.

---

*Prepared as an audit-only deliverable. No code was modified. Fix B1, B2, B3 before release; treat A-a as a
release decision on the tamper-proof guarantee; the remaining High/Medium items are strongly recommended pre-1.0.*
