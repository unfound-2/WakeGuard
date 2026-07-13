# WakeGuard — Production Pre-Release Repository Specification

> **Audience:** the AI (Claude Opus 4.8 High) that will perform the final production
> pre-release audit before App Store submission.
>
> **Purpose of this document:** eliminate repository-discovery work so the audit spends
> its reasoning budget on *finding production issues*, not on *understanding the codebase*.
>
> **What this document is NOT:** it is not the audit. It contains no code-quality review, no
> recommended fixes, no security review, no App Store review, and no speculation. Where
> something looks unusual, incomplete, or important it is recorded — **verbatim and
> un-investigated** — under **§13 Potential Audit Targets** and in the per-slice notes. Treat
> those as leads to verify, not conclusions.
>
> **Provenance:** every file listed below was read in full during discovery (44 Dart files /
> 13,748 lines, the 1,946-line firmware, the native iOS project, build config, and the 8 test
> files). Line numbers are as-read on the `main` branch at commit `03824b1`.

---

## 1. Executive Summary

**WakeGuard** is a two-part product living in one repository:

1. A **Flutter companion app** (`smart_ble_alarm/`) — iOS-first (App Store target), also builds
   for Android. It configures a physical alarm clock over Bluetooth LE, mirrors alarms as
   local-notification backups, and runs the "wake challenge" (QR scan or on-device object photo)
   that dismisses a ringing alarm.
2. **Autonomous clock firmware** (`arduino/WakeGuardClock/WakeGuardClock.ino`) — an Arduino
   Uno + HM-10 BLE + ILI9341 TFT + buzzer that keeps time, stores alarms/tokens in EEPROM, rings,
   and enforces dismissal **on its own with no phone connected**.

The two halves speak a **hand-rolled framed binary BLE protocol** that must agree byte-for-byte.
The phone is never required for an alarm to fire; it is required only to configure the clock and to
run the wake challenge.

**Release state:** first beta, marketing version `0.1.0`, build `1` (`smart_ble_alarm/pubspec.yaml:21`).
Bundle id `com.mekylealam.wakeguardalarm.a74sa4d686b`, team `HX7S7KAF9X`, iOS deployment target 15.5. A prior integration
audit ("Audit 1", `agent reference/Audit 1 report.md`) is fully resolved.

**Highest-value audit surfaces** (detailed in §9 and §14):
- The **BLE wire contract** (`ble_framing.dart`, `ble_payloads.dart`, `alarm.dart`, and the firmware) —
  a length-guarded positional protocol where a byte error silently corrupts clock behavior.
- The **alarm lifecycle & persistence** in `alarm_bloc.dart` (sequential transformer, versioned
  storage, 5-slot enforcement, notification + BLE fan-out).
- The **dismissal / anti-cheat path** (`ringing_dismissal.dart`, `scanner_screen.dart`,
  `item_scan_screen.dart`, `secure_key_datasource.dart`, and firmware `tryDismiss`).
- The **iOS release configuration** (Info.plist purpose strings, absent `PrivacyInfo.xcprivacy`,
  absent `UIBackgroundModes`, absent `ITSAppUsesNonExemptEncryption`, signing style).
- The two **Beta phone-ring modes** (Phone Alarm companion, Dedicated Clock) — foreground-only
  ring engines with no iOS background-audio mode declared.

**Mandatory UI audit.** This specification requires the subsequent auditor to perform an **exhaustive
audit of both UI functionality and UI quality (aesthetics)** for every user-facing surface, equal in
weight to the engineering audit — see **§15 UI Audit Requirements** (the definitive UI blueprint, with a
complete surface inventory), the expanded runtime UI matrix in **§10b**, the per-subsystem UI objectives
in **§9a**, and the gating criteria in **§16 Definition of Production Ready**. A production-ready
conclusion is not permitted unless the UI criteria in §16 have been verified by exercising the running
app, not by reading code alone.

**Non-target scaffolding (do not audit):** `smart_ble_alarm/macos/`, `linux/`, `windows/`, `web/`
are default Flutter platform folders. The App Store target is iOS; Android is a secondary buildable
target that is present but not the submission surface.

---

## 2. Repository Overview

| Property | Value |
|---|---|
| Git root | `/Users/aaron/development/Projects/Alarm-Clock` |
| Branch | `main` (origin: `github.com/cowfollowdog/WakeGuard.git`) |
| Tracked files | 199 total (185 under `smart_ble_alarm/`, 4 arduino, 4 docs, others) |
| App source | `smart_ble_alarm/lib/` — 44 Dart files, 13,748 lines |
| Firmware | `arduino/WakeGuardClock/WakeGuardClock.ino` — 1,946 lines C++ |
| Tests | `smart_ble_alarm/test/` — 8 files (CLAUDE.md cites 39 passing cases) |
| Architecture | Clean architecture (core / data / domain / presentation) + `flutter_bloc` |
| State mgmt | `flutter_bloc` (BLoCs + Cubits) + a few module-level `ValueNotifier`s |
| Persistence | `shared_preferences` (alarms/settings/history/timers/flags) + `flutter_secure_storage` (one backup-code key) |
| App Store target | iOS (bundle `com.mekylealam.wakeguardalarm.a74sa4d686b`, team `HX7S7KAF9X`, iOS 15.5+) |

### Existing in-repo documentation (source-of-truth ranking)
- `agent reference/CLAUDE.md` (18 KB) — **current** engineering brief; architecture, protocol, alarm model, conventions, iOS/TestFlight, "do not change" list. **Most authoritative.**
- `README.md` — product + protocol overview (current).
- `PROJECT_LOG.md` — attribution + full feature/implementation log (current).
- `agent reference/Smart BLE Alarm Specification.md` (62 KB) — the **original** technical design spec (hardware, firmware, BLE, crypto, Flutter). Design intent; code has since deviated in documented places — treat as historical where it conflicts with CLAUDE.md/code.
- `agent reference/UI Design.md` — UI & navigation spec.
- `agent reference/Audit 1 report.md` — earlier integration audit, all findings marked resolved.

Where these conflict, CLAUDE.md + README + current code win (per README:142).

---

## 3. Repository Tree

Production-relevant tracked files (scaffolding platform folders, Pods, generated tool caches,
and binary assets collapsed):

```
Alarm-Clock/
├── README.md                              # product + protocol overview (current)
├── PROJECT_LOG.md                         # attribution + feature log
├── .gitignore                             # ignores /build/ (but see stray tracked artifact below)
├── .vscode/settings.json
├── agent reference/                       # ← OUTPUT DOCS FOLDER (this file lives here)
│   ├── CLAUDE.md                          # authoritative engineering brief
│   ├── Smart BLE Alarm Specification.md   # original design spec (historical where it conflicts)
│   ├── UI Design.md                       # UI/navigation spec
│   └── Audit 1 report.md                  # prior integration audit (resolved)
├── build/
│   └── ios/SourcePackages/workspace-state.json   # STRAY tracked build artifact despite /build/ ignore
├── arduino/
│   ├── WakeGuardClock/WakeGuardClock.ino  # THE CLOCK FIRMWARE (1946 lines) — BLE protocol peer
│   ├── BuzzerTest1_SteadyDC/…             # diagnostic sketches (active buzzer)
│   ├── BuzzerTest2_Tone/…                 # tone() 2 kHz (passive piezo test)
│   └── BuzzerTest3_BitBang/…              # bit-bang ~1 kHz
└── smart_ble_alarm/                       # THE FLUTTER APP
    ├── pubspec.yaml / pubspec.lock        # deps + resolved versions; version 0.1.0+1
    ├── analysis_options.yaml
    ├── README.md
    ├── lib/
    │   ├── main.dart                      # entry point + 5-way home routing
    │   ├── core/
    │   │   ├── ble/
    │   │   │   ├── ble_payloads.dart      # byte-frame builders (0x01/0x02/0x06/0x0C/0x0D)
    │   │   │   └── clock_sync.dart         # sync orchestration + weather push + global notifiers
    │   │   ├── notifications/notification_service.dart   # backup local notifications
    │   │   ├── audio/alarm_sound.dart      # runtime-synthesized WAV (Dedicated Clock ring)
    │   │   ├── theme/                       # Liquid Glass design system
    │   │   │   ├── glass.dart, wake_widgets.dart, app_theme.dart,
    │   │   │   ├── app_colors.dart, app_background.dart
    │   │   ├── ui/app_snackbar.dart        # non-queueing snackbars
    │   │   └── utils/alarm_time_utils.dart # time-of-day + next-occurrence formatting
    │   ├── data/
    │   │   ├── datasources/
    │   │   │   ├── ble_framing.dart         # SOF/EOF/ESC/XOR codec (protocol core)
    │   │   │   ├── secure_key_datasource.dart # ONE global HMAC backup-code token
    │   │   │   ├── image_recognition_datasource.dart # Google ML Kit labeling
    │   │   │   └── weather_datasource.dart  # ipapi.co + open-meteo (network egress)
    │   │   └── repositories/
    │   │       ├── ble_repository_impl.dart          # real flutter_blue_plus HM-10 transport
    │   │       └── simulated_ble_repository_impl.dart # dev simulator (device 'simulated_device')
    │   ├── domain/
    │   │   ├── entities/alarm.dart          # Alarm entity + wire getters + syncHash + JSON
    │   │   ├── repositories/ble_repository.dart # abstract port
    │   │   └── usecases/print_qr_code.dart  # renders/prints the single backup QR (PDF)
    │   └── presentation/
    │       ├── blocs/
    │       │   ├── alarm_bloc/alarm_bloc.dart           # alarms: state/persist/notify/sync/ring
    │       │   ├── ble_bloc/{ble_bloc,ble_event,ble_state}.dart # connection lifecycle
    │       │   ├── settings_bloc/settings_bloc.dart     # all settings + persistence
    │       │   ├── timer_cubit/countdown_timer_cubit.dart # timer mirror
    │       │   └── history_cubit/dismissal_history_cubit.dart # dismissal log
    │       ├── screens/
    │       │   ├── main_screen.dart          # tab shell + lifecycle + inbound frames + setting pushes
    │       │   ├── setup_screen.dart          # pairing + permission requests
    │       │   ├── onboarding_screen.dart     # first-run carousel
    │       │   ├── alarm_edit_screen.dart     # alarm authoring (largest UI file, 1256 lines)
    │       │   ├── scanner_screen.dart        # QR scan → 0x09 dismiss
    │       │   ├── item_scan_screen.dart      # object photo → ML match → 0x09 dismiss + 3-min gate
    │       │   ├── settings_screen.dart        # settings surface (also usable as tab)
    │       │   ├── dismissal_history_screen.dart
    │       │   ├── dedicated_clock_screen.dart # Beta: spare-phone standby clock + ring engine
    │       │   └── tabs/
    │       │       ├── home_tab.dart, alarms_tab.dart,
    │       │       ├── clock_tab.dart (ClockDeviceScreen), display_tab.dart
    │       └── widgets/
    │           ├── ringing_dismissal.dart     # single-source-of-truth dismiss action
    │           ├── liquid_glass_tab_bar.dart
    │           └── create_timer_sheet.dart
    ├── ios/                                 # ← App Store target (see §7)
    │   ├── Runner/Info.plist, AppDelegate.swift, SceneDelegate.swift, …
    │   ├── Runner.xcodeproj/project.pbxproj
    │   ├── Podfile, Podfile.lock
    │   └── RunnerTests/RunnerTests.swift    # empty placeholder
    ├── android/                             # secondary target (not submission surface)
    │   ├── app/build.gradle.kts             # release signs with DEBUG keys (TODO)
    │   └── app/src/main/AndroidManifest.xml
    ├── test/                                # 8 test files (see §7 test inventory)
    ├── assets/branding/wakeguard_logo.png   # the ONLY bundled asset
    └── macos/ · linux/ · windows/ · web/    # default Flutter scaffolding — NOT audit targets
```

### File inventory & classification

Classification uses the taxonomy in the brief. "PC" = production-critical.

**Entry point & `core/`**

| File | Classification | PC | Responsibility (one line) |
|---|---|---|---|
| `lib/main.dart` | Core Logic / State Mgmt | ✅ | Sole entry point; bootstraps prefs/BLE/notifications, wires all blocs, 5-way home route. |
| `lib/core/ble/ble_payloads.dart` | Core Logic (protocol) | ✅ | Pure byte-frame builders for 0x01/0x02/0x06/0x0C/0x0D. |
| `lib/core/ble/clock_sync.dart` | Core Logic / State Mgmt | ✅ | Full sync sequence + weather push; global `lastClockSync`/`clockSyncInProgress` notifiers. |
| `lib/core/notifications/notification_service.dart` | Notifications / Background / Permissions | ✅ | Schedules backup local notifications mirroring enabled alarms; requests notif perms. |
| `lib/core/audio/alarm_sound.dart` | Alarm System / Assets(gen) | ✅ | Generates 16-bit PCM WAV alarm tone at runtime (no shipped audio asset). |
| `lib/core/theme/app_background.dart` | UI / State Mgmt | ❌ | Animated background styles + global `appBackgroundStyle` notifier. |
| `lib/core/theme/app_colors.dart` | UI / Settings | ❌ | Color tokens + accent-string resolution. |
| `lib/core/theme/app_theme.dart` | UI / Settings | ❌ | Builds M3 light/dark ThemeData + status-bar overlay. |
| `lib/core/theme/glass.dart` | UI | ❌ | GlassTheme extension + GlassBackground + GlassCard. |
| `lib/core/theme/wake_widgets.dart` | UI | ❌ | Shared component library (sections/buttons/pills/rows/empty states/logo). |
| `lib/core/ui/app_snackbar.dart` | UI | ❌ | Non-queueing snackbar helper. |
| `lib/core/utils/alarm_time_utils.dart` | Core Logic (util) | ✅* | Canonical time/next-occurrence formatting choke point. |

**`data/` + `domain/`**

| File | Classification | PC | Responsibility |
|---|---|---|---|
| `lib/data/datasources/ble_framing.dart` | Core Logic | ✅ | SOF/EOF/ESC + XOR-checksum codec; max payload 15 B. |
| `lib/data/datasources/secure_key_datasource.dart` | Encryption / Storage | ✅ | One global 8-byte HMAC-SHA256 backup token; `deleteKey` is a no-op. |
| `lib/data/datasources/image_recognition_datasource.dart` | Camera/Scanner | ✅ | On-device Google ML Kit image labeling + `matchesLabel`. |
| `lib/data/datasources/weather_datasource.dart` | Networking | ❌ | Best-effort weather via ipapi.co + open-meteo; null on any failure. |
| `lib/data/repositories/ble_repository_impl.dart` | Core Logic (transport) | ✅ | Real HM-10 link (FFE0/FFE1), write mutex, 20-B chunking. |
| `lib/data/repositories/simulated_ble_repository_impl.dart` | Core Logic (test double) | ❌ | In-memory fake backend (`simulated_device`). |
| `lib/domain/entities/alarm.dart` | Alarm System | ✅ | Entity + wire getters + `syncHash` (FNV-1a) + JSON. |
| `lib/domain/repositories/ble_repository.dart` | Core Logic (interface) | ✅ | Abstract BLE port both backends satisfy. |
| `lib/domain/usecases/print_qr_code.dart` | Backup Code/QR | ✅ | Renders + prints the single backup QR as a PDF. |

**`presentation/blocs/`**

| File | Classification | PC | Responsibility |
|---|---|---|---|
| `.../alarm_bloc/alarm_bloc.dart` | State Mgmt / Alarm / Storage | ✅ | Alarm list, persistence (v2 envelope), notification backups, BLE sync, ring state. |
| `.../ble_bloc/ble_bloc.dart` | State Mgmt / BLE | ✅ | On-demand connection lifecycle; bounded auto-connect (≤3). |
| `.../ble_bloc/ble_event.dart` | State Mgmt | ✅ | BLE event contract. |
| `.../ble_bloc/ble_state.dart` | State Mgmt | ✅ | Disconnected/Scanning/Connecting/Connected. |
| `.../settings_bloc/settings_bloc.dart` | Settings / Storage | ✅ | 22 settings fields; persists each; primes `appBackgroundStyle`. |
| `.../timer_cubit/countdown_timer_cubit.dart` | State Mgmt / Storage | ❌ | App-side mirror of clock-run timers. |
| `.../history_cubit/dismissal_history_cubit.dart` | State Mgmt / Storage | ❌ | Capped (100) dismissal log. |

**`presentation/screens/` + `widgets/`**

| File | Classification | PC | Responsibility |
|---|---|---|---|
| `.../screens/main_screen.dart` | UI / State Mgmt (glue) | ✅ | Tab shell; lifecycle connect/release; inbound 0x08/0x89; live 0x06/0x0C/0x0D pushes; banners. |
| `.../screens/setup_screen.dart` | UI / Permissions / BLE | ✅ | Pairing; requests BLE + location perms; persists `rememberedDeviceId`. |
| `.../screens/onboarding_screen.dart` | UI | ❌ | First-run carousel; sets `hasSeenOnboarding`. |
| `.../screens/alarm_edit_screen.dart` | Alarm System / UI | ✅ | Alarm authoring incl. wake-challenge, snooze, volume, fade; camera capture. |
| `.../screens/scanner_screen.dart` | Camera/Scanner | ✅ | QR verify → 0x09 dismiss. |
| `.../screens/item_scan_screen.dart` | Camera/Scanner | ✅ | Object photo → ML match → 0x09; 3-min backup-QR gate. |
| `.../screens/settings_screen.dart` | Settings | ✅ | All prefs; developer/unpair/connect/dedicated entry points; destructive reset. |
| `.../screens/dismissal_history_screen.dart` | UI | ❌ | Read-only dismissal log. |
| `.../screens/dedicated_clock_screen.dart` | UI / Alarm / Background(fg) | ✅† | Beta standby clock that detects the alarm minute and rings in-foreground. |
| `.../screens/tabs/home_tab.dart` | UI / State Mgmt | ✅ | Home dashboard; primary ring surface; sync entry. |
| `.../screens/tabs/alarms_tab.dart` | Alarm System / UI | ✅ | Alarm list (swipe-delete+undo, enable toggle, ringing card) + timers. |
| `.../screens/tabs/clock_tab.dart` | Settings / State Mgmt | ✅ | `ClockDeviceScreen`: BLE reconnect/forget, sync panel, backup-code print. |
| `.../screens/tabs/display_tab.dart` | Settings | ✅ | Physical-clock display config (0x06/0x0D/weather). |
| `.../widgets/ringing_dismissal.dart` | State Mgmt / UI | ✅ | Single-source dismiss action across 3 surfaces. |
| `.../widgets/liquid_glass_tab_bar.dart` | UI | ❌ | Floating tab bar chrome. |
| `.../widgets/create_timer_sheet.dart` | UI / State Mgmt | ✅ | Only timer-creation surface; sends 0x0A. |

\* time-format util is load-bearing for correctness of displayed alarm/sync times.
† production-critical only when Dedicated Clock mode is enabled (off by default).

---

## 4. Architecture

### 4.1 Layering
Clean architecture under `smart_ble_alarm/lib/`:
- **domain** — pure entities + ports (`alarm.dart`, `ble_repository.dart`, `print_qr_code.dart`). No Flutter/plugin deps except `equatable`/`flutter_blue_plus` types in the port.
- **data** — datasources (framing, secure key, image recognition, weather) + repository implementations (real + simulated).
- **core** — cross-cutting: BLE payload/sync, notifications, audio, theme, ui, utils.
- **presentation** — BLoCs/Cubits + screens/tabs/widgets.

### 4.2 Entry point & startup sequence (`lib/main.dart`)
`main()` (async):
1. `WidgetsFlutterBinding.ensureInitialized()` (`main.dart:24`).
2. `SharedPreferences.getInstance()` (`:25`).
3. Read `rememberedDeviceId` pref (`:26`).
4. Select BLE backend: `SimulatedBleRepositoryImpl` iff `rememberedDeviceId == 'simulated_device'`, else `BleRepositoryImpl` (`:28-33`).
5. `NotificationService().init()` wrapped in `try/catch(_){}` so notif/perm failure never blocks launch (`:38-41`).
6. `runApp(SmartAlarmApp(...))` (`:43-50`).

`_SmartAlarmAppState` hydrates in-memory mode fields from prefs (`:76-91`): `setupSkipped`,
`dedicatedClockEnabled`, `rememberedDeviceId`, `_backendGeneration`. A `KeyedSubtree` keyed on
`_backendGeneration` (`:181`) rebinds all blocs when the developer-mode backend is swapped; the
abandoned repository is disposed manually (`:102/:118`).

Provider/bloc wiring (`:183-217`) inside the keyed subtree:
- `RepositoryProvider<BleRepository>.value`
- `SettingsBloc(prefs)..add(LoadSettingsEvent())`
- `BleConnectionBloc(...)` + `AutoConnectEvent(rememberedDeviceId!)` when remembered
- `AlarmBloc(bleRepository, prefs, notificationService)..add(LoadAlarmsEvent())`
- `CountdownTimerCubit(prefs)`, `DismissalHistoryCubit(prefs)`

`MaterialApp` is built inside a `BlocBuilder<SettingsBloc>` gated on theme/accent only (`:222-224`);
a `builder:` wraps every route in an `AnnotatedRegion<SystemUiOverlayStyle>` (`:259-272`).

### 4.3 Home routing (declarative, highest precedence first — `main.dart:276-318`)
1. `dedicatedClockEnabled` → `DedicatedClockScreen`
2. else `rememberedDeviceId != null` → `MainScreen` (paired; simulator vs real chooses exit/unpair callbacks)
3. else `setupSkipped` → `MainScreen` (offline, `onConnectClock`)
4. else `hasSeenOnboarding` → `SetupScreen`
5. else → `OnboardingScreen`

Routing pref keys: `rememberedDeviceId` (String; `'simulated_device'` sentinel), `setupSkipped`,
`dedicatedClockEnabled`, `hasSeenOnboarding`.

### 4.4 State management
- BLoCs/Cubits: `AlarmBloc`, `BleConnectionBloc`, `SettingsBloc`, `CountdownTimerCubit`, `DismissalHistoryCubit`.
- **AlarmBloc uses a custom sequential transformer** (`asyncExpand`, `alarm_bloc.dart:226-227`) to serialize events — a deliberate choice (comment `:206-212`); concurrent handling would clobber pending-delete/sync-status sets. **CLAUDE.md §11 marks this "do not change".**
- Module-level `ValueNotifier`s (global singletons, created outside `main`):
  - `clock_sync.dart:45` `lastClockSync : ValueNotifier<DateTime?>`
  - `clock_sync.dart:50` `clockSyncInProgress : ValueNotifier<bool>`
  - `app_background.dart:34` `appBackgroundStyle : ValueNotifier<AppBackgroundStyle>`

### 4.5 Persistence architecture
- **`shared_preferences`** keys: `saved_alarms` (v2 envelope `{"version":2,"alarms":[…]}`, legacy v1 bare-list migration in `parseStoredAlarms`), `pending_alarm_deletes`, `synced_alarm_hashes`, `active_timers`, `dismissal_history`, plus settings keys (`is24HourTime`, `themeString`, `accentColorString`, `clockThemeLight`, `clockAccentIndex`, `clockShowSeconds`, `clockShowDate`, `clockShowDayOfWeek`, `clockDateFormat`, `clockSleepEnabled`, `clockSleepStart`, `clockSleepEnd`, `showWeather`, `weatherFahrenheit`, `defaultQrRequired`, `animationsEnabled`, `autoTimeSync`, `backupNotificationsEnabled`, `phoneAlarmEnabled`, `phoneAlarmRequireCharging`, `dedicatedClockEnabled`, `appBackground`) and routing flags (`rememberedDeviceId`, `setupSkipped`, `hasSeenOnboarding`).
- **`flutter_secure_storage`**: one key `alarm_key_global` holding the 16-byte HMAC key (`secure_key_datasource.dart:14`).
- **Firmware EEPROM** (separate persistence, on the clock): magic `0x5A`, `EE_VERSION=3`, display flags/theme/accent, driftPPM, 5 `AlarmConfig` slots. Weather + sleep-window deliberately RAM-only.

### 4.6 Platform communication
- **BLE**: `flutter_blue_plus` → HM-10 transparent serial bridge, service `FFE0` / characteristic `FFE1`. Framed protocol (`ble_framing.dart` ↔ firmware). 20-byte MTU chunking; writes serialized by a mutex chain (`ble_repository_impl.dart`).
- **Notifications**: `flutter_local_notifications` + `timezone`/`flutter_timezone`.
- **Camera**: `mobile_scanner` (QR) and `image_picker` + `google_mlkit_image_labeling` (object).
- **Print**: `printing` + `pdf`.
- **Audio/keepalive** (Dedicated Clock only): `audioplayers` + `wakelock_plus`.
- **Network** (weather only): raw `dart:io HttpClient` to `ipapi.co` + `api.open-meteo.com`.
- No custom platform channels; `AppDelegate.swift` registers plugins only.

### 4.7 Release vs debug configuration
- iOS build configs: Debug / Profile / Release (`ios/Flutter/*.xcconfig`, project.pbxproj). Version flows from `pubspec.yaml` `version:` → `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`.
- Simulator backend gated by `rememberedDeviceId == 'simulated_device'`; "Enter developer mode" entry only when `kDebugMode` (`main.dart` passes `onEnterDeveloperMode: kDebugMode ? … : null`).
- Android release currently signs with **debug keys** (`android/app/build.gradle.kts`, TODO).

### 4.8 Architecture diagram (text)

```
                         ┌──────────────────────────────────────────────┐
                         │                 Flutter App                   │
                         │                                               │
   Onboarding/Setup ──▶  │  main.dart (5-way route) ──▶ MainScreen shell │
                         │        │                         │            │
        ┌────────────────┼────────┼───────────┬─────────────┼──────────┐ │
        │ SettingsBloc   │ AlarmBloc          │ BleConnBloc │ Timer/Hist│ │
        │ (prefs)        │ (prefs + secure)   │ (fbp)       │ (prefs)   │ │
        └───────┬────────┴─────┬──────────────┴──────┬──────┴───────────┘ │
                │              │                      │                    │
     appBackgroundStyle   NotificationService    BleRepository (port)     │
        (notifier)        (local notifications)   ├─ BleRepositoryImpl ───┼──┐
                                                   └─ SimulatedBleRepo     │  │
                         │  clock_sync.dart  ──uses──▶ ble_payloads.dart   │  │
                         │  (sequence + weather)        │                  │  │
                         │                              ▼                  │  │
                         │                        ble_framing.dart (codec) │  │
                         └──────────────────────────────────────────────┘  │
                                                                            │ BLE (HM-10
                                                                            │  FFE0/FFE1,
                                                                            │  20-B chunks,
                                                                            │  framed bytes)
                                                                            ▼
                         ┌──────────────────────────────────────────────────────┐
                         │        WakeGuardClock.ino  (autonomous firmware)       │
                         │  pumpBle → decode frame → handleFrame dispatch          │
                         │  software clock (drift-corrected) · EEPROM (5 slots +   │
                         │  tokens + settings) · ring engine (token-gated) ·       │
                         │  ILI9341 display · buzzer(D9) · sleep window · watchdog  │
                         └──────────────────────────────────────────────────────┘
```

### 4.9 The BLE protocol (contract summary — verify app ↔ firmware agreement)
Framing (`ble_framing.dart` ↔ firmware decoder): `SOF(0x5B '[') · escaped(cmd,len,data…,cs) · EOF(0x5D ']')`,
`ESC=0x5C`, uniform escaping of any body byte equal to SOF/EOF/ESC, `cs = cmd^len^data…`, **max payload 15 B**.

| Cmd | Name | Payload | ACK |
|---|---|---|---|
| 0x01 | TIME_SYNC | uint32 BE **local** epoch secs (UTC + tz offset; phone owns DST) | 0x81 |
| 0x02 | ALARM_ADD (upsert) | **9 B** `[id,hour,min,dayMask,qrRequired,snoozeCount,snoozeDur,volume,gradualWake]` (bytes 6–9 length-guarded) | 0x82 (echoes id) |
| 0x03 | ALARM_DEL | `[id]` | 0x83 |
| 0x04 / 0x05 | SYNC_START / SYNC_END | — (brackets a batch; EEPROM flush at END) | 0x84 / 0x85 |
| 0x06 | SETTINGS (display) | `[flags,theme,accent]` (flags: bit0=24h,1=seconds,2=date,3=dayOfWeek,4-5=dateFormat) | 0x86 |
| 0x07 | QR_KEY | `[id, token×8]` | 0x87 |
| 0x09 | DISMISS | `[id, token×8]` (firmware `memcmp`; zero token OK if unsecured) | 0x89 on success only |
| 0x0A / 0x0B | TIMER_SET / TIMER_STOP | uint32 secs / — | 0x8A / 0x8B |
| 0x0C | WEATHER | `[int8 temp, condCode]` (0xFF=hide) RAM-only | 0x8C |
| 0x0D | DISPLAY_SLEEP | `[enabled,startH,startM,endH,endM]` RAM-only | 0x8D |
| 0x88 | RING_ACK (app→clock) | app confirms it saw 0x08 (stops rebroadcast) | — |
| 0x08 | NOTIFY_RING (clock→app) | `[alarmId]` re-broadcast every 3 s until 0x88 | — |
| 0xFF | CMD_ERROR (clock→app) | `[errcode]` (0x02 checksum / 0x03 too-long / 0x04 invalid cmd) | — |

---

## 5. Runtime Flow Maps

Each flow lists files in execution order, platform interactions, and key dependencies. "→" is call/dispatch order.

### 5.1 App startup / Cold launch
`main.dart` `main()` → prefs → BLE backend select → `NotificationService.init()` (tz load, plugin init, iOS/Android perm request) → `runApp` → `SettingsBloc.LoadSettingsEvent` (also primes `appBackgroundStyle`) → `BleConnectionBloc.AutoConnectEvent` (if remembered) → `AlarmBloc.LoadAlarmsEvent` (loads `saved_alarms`/`pending_alarm_deletes`/`synced_alarm_hashes`, reschedules backups) → 5-way route.
Platform: SharedPreferences, secure storage (lazy), local-notifications init, BLE adapter.

### 5.2 Warm launch / Background resume / State restoration
`main_screen.dart` `_MainScreenState` is a `WidgetsBindingObserver`: on **resume** dispatches `ReconnectEvent` (re-`AutoConnect` for `_autoReconnectDeviceId` if idle, `ble_bloc.dart:275`); on **pause/background** dispatches `ReleaseConnectionEvent` (tears down subs, disconnects, keeps remembered id, `ble_bloc.dart:290`). No background BLE by design (CLAUDE.md §11). State restoration = re-reading prefs on cold start (no `RestorationMixin`).

### 5.3 Alarm creation
`alarm_edit_screen.dart` (fields → `Alarm`) → validations (5-slot cap via `AlarmBloc.maxHardwareAlarms`, repeat-mask non-zero, item label present) → `_nextAlarmId` (scans 1..255) → `AddOrUpdateAlarmEvent(alarm, connectedDevice, rotateSecureKey: isNew)` → `alarm_bloc.dart:_onAddOrUpdateAlarm`.
Camera at edit time: `image_picker` camera → `image_recognition_datasource.labelImageFile` → label picker.

### 5.4 Alarm persistence
`alarm_bloc.dart:_onAddOrUpdateAlarm/_onDeleteAlarm` → `_saveAlarms` writes v2 envelope to `saved_alarms`; `_savePendingDeletes` → `pending_alarm_deletes`; `_saveSyncedHashes` → `synced_alarm_hashes`. Load path `parseStoredAlarms` migrates legacy v1. All decoders wrap `try/catch(_){}`.

### 5.5 Alarm scheduling — two independent schedulers
1. **Clock (authoritative)**: `_sendAlarmToDevice` (`alarm_bloc.dart:525`) → `0x02` `BlePayloads.alarm(alarm)`; if `qrRequired` also `0x07` token → firmware EEPROM slot; firmware software clock fires it.
2. **Phone backup**: `_rescheduleBackupAlarms` → `NotificationService.syncAlarms` → per-active-alarm one-shot or per-weekday `zonedSchedule` (`notification_service.dart`). Gated on `backupNotificationsEnabled` (inside the service). `_notificationId = alarmId*10 + weekday`.

### 5.6 Alarm modification
Same event as creation (`AddOrUpdateAlarmEvent`, upsert by id). Enable/disable toggled inline on the Alarms card by flipping `0x80` in `dayMask` (`alarms_tab.dart:344-346`). `syncHash` diff (`alarm.dart:110-127`) decides whether the clock is "out of sync".

### 5.7 Alarm ringing
Firmware fires → sends `0x08 [alarmId]` (rebroadcast every 3 s). App: `main_screen.dart:_listenForDeviceFrames` decodes → `AlarmBloc.SetRingingAlarmEvent(alarmId)` (sets `ringingAlarmId`, stamps `ringingSince`) and sends `0x88` ack. Ring UI renders on 3 surfaces via `ringing_dismissal.dart`: global banner (`main_screen`), Home card (`home_tab._ringingCard`), Alarms card (`alarms_tab`, error tint + "Ringing now" pill).
**Dedicated Clock mode** (no hardware): `dedicated_clock_screen.dart` 1-s ticker `_maybeFire` matches the minute against `AlarmBloc.state.alarms`, plays looping WAV via `audioplayers`.

### 5.8 Alarm dismissal
Branch in `ringing_dismissal.dart`:
- **No challenge** (`!qrRequired`): `_dismissNoTask` → `0x09 [id, 0×8]` (zero token) → `SetRingingAlarmEvent(null)` → history `'Dismiss'`.
- **Object** (`usesItemScan`): push `item_scan_screen.dart` → camera photo → `image_recognition_datasource.matchesLabel` → on match `0x09 [id, token]` (token from `secure_key_datasource.getDailyToken`) → clear ring → history `'Item'`. Backup-QR gate opens 3 min after `ringingSince`.
- **QR** (`qrRequired`, no item): push `scanner_screen.dart` → `mobile_scanner` → `verifyQRCode` → `0x09 [id, token]` → clear ring → history `'QR'`.
Firmware `tryDismiss` `memcmp`s the token; emits `0x89` only on success (wrong token keeps ringing). A one-time alarm auto-disables its `0x80` bit on ring-clear (`alarm_bloc.dart:_onSetRingingAlarm`).

### 5.9 Snooze
Firmware side: per-alarm `snoozeCount`/`snoozeMinutes` in EEPROM; button/token snooze in ring engine. Dedicated Clock side: `dedicated_clock_screen.dart:_snooze` (`_canSnooze` requires `snoozeEnabled && snoozeMaxCount>0 && used<max`), stops ring, arms `Timer(minutes: snoozeDurationMinutes)`. No free "dismiss anyway".

### 5.10 Notification scheduling / delivery / actions
Scheduling: §5.5(2). Delivery: OS-driven at scheduled zoned time (Android `fullScreenIntent`+alarm category+`exactAllowWhileIdle`; iOS `interruptionLevel: timeSensitive`, weekly via `DateTimeComponents.dayOfWeekAndTime`). **Actions:** none defined — the backup notification cannot run scan/QR dismissal (by design; it is a safety net only). Android manifest registers boot-replay receivers so schedules survive reboot.

### 5.11 Camera scan flow
- Edit-time capture: `alarm_edit_screen.dart` → `image_picker` camera → `image_recognition_datasource` (labels top-5).
- Dismissal QR: `scanner_screen.dart` → `mobile_scanner` live preview.
- Dismissal object: `item_scan_screen.dart` → `image_picker` camera → ML labeling → match.
iOS permission surfaced by the plugins (no explicit `permission_handler` prompt on these screens); string `NSCameraUsageDescription` in Info.plist.

### 5.12 Permission requests
`setup_screen.dart` requests `bluetoothScan`, `bluetoothConnect`, `locationWhenInUse` via `permission_handler` before scanning. Notification + exact-alarm perms requested in `notification_service.init()` at startup. Camera requested implicitly by `image_picker`/`mobile_scanner`.

### 5.13 Settings loading / saving
Load: `SettingsBloc.LoadSettingsEvent` reads all keys, primes `appBackgroundStyle`. Save: each `*Event` persists its key(s) and emits. **BLE pushes are NOT in SettingsBloc** — `main_screen.dart` `MultiBlocListener` reacts to state changes and pushes `0x06` (display), `0x0D` (sleep), `0x0C` (weather via `pushWeatherToClock`), and re-runs notification scheduling on the backup toggle. Sync engine `clock_sync.dart:syncConnectedClock` runs the full 0x04→0x01→alarms→0x06→0x0D→0x05 sequence (+ unawaited weather), coalesced by `clockSyncInProgress`, one retry after 600 ms.

---

## 6. Dependency Analysis

Direct dependencies (`pubspec.yaml`) with resolved versions (`pubspec.lock`) and the iOS-linked native
plugin set confirmed from `ios/Runner/GeneratedPluginRegistrant.m`. "★" marks packages that touch a
critical subsystem and warrant extra audit attention.

| Package | Resolved | Native iOS | Purpose | Touches | ★ |
|---|---|---|---|---|---|
| `flutter_blue_plus` | 2.3.10 | flutter_blue_plus_darwin 9.0.3 | HM-10 BLE transport | BLE, permissions | ★ |
| `flutter_secure_storage` | 10.3.1 | _darwin 0.3.2 | Backup-code key (Keychain) | storage, encryption | ★ |
| `crypto` | 3.0.7 | no (Dart) | HMAC-SHA256 tokens | encryption | ★ |
| `flutter_local_notifications` | 22.0.1 | yes | Backup alarm notifications | notifications, background, permissions | ★ |
| `timezone` | 0.11.1 | no (Dart) | Zoned scheduling | notifications | ★ |
| `flutter_timezone` | 5.1.0 | yes | Resolve local tz | notifications | ★ |
| `mobile_scanner` | 7.2.0 | yes (darwin) | QR dismissal scan | camera, permissions | ★ |
| `google_mlkit_image_labeling` | 0.14.2 | yes (GoogleMLKit pods) | On-device object recognition | camera, ML | ★ |
| `image_picker` | 1.2.3 | image_picker_ios | Camera capture | camera, permissions | ★ |
| `permission_handler` | 12.0.3 | permission_handler_apple 9.4.10 | BLE/camera/location perms | permissions | ★ |
| `printing` | 5.15.0 | yes | AirPrint the backup QR | print | |
| `pdf` | 3.13.0 | no (Dart) | Build the QR PDF | print | |
| `audioplayers` | **6.8.1** (^6.1.0) | audioplayers_darwin 6.5.0 | Loop ring tone (Dedicated Clock) | audio | ★ |
| `wakelock_plus` | **1.6.1** (^1.2.8) | yes | Keep screen awake (Dedicated Clock) | background(fg) | ★ |
| `flutter_bloc` | 9.1.1 | no | State management | core | |
| `equatable` | 2.0.8 | no | Value equality | core | |
| `shared_preferences` | 2.5.5 | shared_preferences_foundation | App persistence | storage | ★ |
| `cupertino_icons` | 1.0.9 | no | Icons | UI | |
| `flutter_lints` (dev) | 6.0.0 | no | Lints | build | |

Notable transitive native pods pulled into iOS: the **GoogleMLKit** stack (MLKitVision / ImageLabeling /
Common), GoogleUtilities, GoogleDataTransport, nanopb, GTMSessionFetcher, PromisesObjC. `package_info_plus`
is registered on iOS (transitive). No `package:http` — weather uses raw `dart:io HttpClient`.

Subsystem impact summary:
- **Alarms**: `flutter_blue_plus`, `flutter_local_notifications`, `timezone`/`flutter_timezone`, `shared_preferences`, `audioplayers`, `wakelock_plus`.
- **Notifications**: `flutter_local_notifications`, `timezone`, `flutter_timezone`.
- **Storage**: `shared_preferences`, `flutter_secure_storage`.
- **Permissions**: `permission_handler`, `flutter_blue_plus`, `image_picker`, `mobile_scanner`, `flutter_local_notifications`.
- **Background execution**: `wakelock_plus` (screen), `flutter_local_notifications` (OS scheduler). No BLE background.
- **Camera / ML**: `mobile_scanner`, `image_picker`, `google_mlkit_image_labeling`.
- **Encryption**: `crypto` (HMAC), `flutter_secure_storage` (Keychain).
- **Networking**: none as a package — weather via `dart:io` to ipapi.co + open-meteo.

---

## 7. Native iOS Overview

App Store target. Files under `smart_ble_alarm/ios/`.

| File | Role | Key facts |
|---|---|---|
| `Runner/Info.plist` | App Info plist | Display name **WakeGuard**; identity keys build-variable-driven; purpose strings present (below); **no** `UIBackgroundModes`, **no** `ITSAppUsesNonExemptEncryption`, **no** URL schemes/ATS. iPhone orientations: Portrait + Landscape L/R (no upside-down). |
| `Runner/AppDelegate.swift` | App delegate | `@main FlutterAppDelegate` + `FlutterImplicitEngineDelegate`; registers plugins only. No AVAudioSession, no background task, no method channels. |
| `Runner/SceneDelegate.swift` | Scene delegate | Empty `FlutterSceneDelegate`. |
| `Runner/Runner-Bridging-Header.h` | Bridging header | Imports `GeneratedPluginRegistrant.h` only. |
| `Runner/Base.lproj/LaunchScreen.storyboard` | Launch screen | Default Flutter (centered LaunchImage, white bg). |
| `Runner/Base.lproj/Main.storyboard` | Main scene | Single `FlutterViewController`. |
| `Runner/Assets.xcassets/AppIcon.appiconset` | Icons | Full iPhone/iPad set incl. 1024² marketing icon. |
| `Flutter/Debug.xcconfig` / `Release.xcconfig` | Build config | Include Pods + Generated xcconfig. |
| `Podfile` | CocoaPods | `platform :ios, '15.5'`, `use_frameworks!`, post_install forces deployment target 15.5. |
| `Podfile.lock` | Pod lock | CocoaPods 1.16.2; 11 plugin pods. **`audioplayers`/`wakelock_plus` NOT in the pod list** — project also uses a Flutter SwiftPM package `FlutterGeneratedPluginSwiftPackage` (SPM + CocoaPods hybrid). |
| `Runner.xcodeproj/project.pbxproj` | Xcode project | Bundle id `com.mekylealam.wakeguardalarm.a74sa4d686b`; `DEVELOPMENT_TEAM = HX7S7KAF9X`; `CODE_SIGN_IDENTITY = "iPhone Developer"`; **no explicit `CODE_SIGN_STYLE` on Runner**; deployment target 15.5; device family 1,2; bitcode off; version from `$(FLUTTER_BUILD_NAME/NUMBER)`. |
| `Runner.xcodeproj/.../Runner.xcscheme` | Scheme | Test→RunnerTests(Debug), Archive→Release, Profile→Profile. |
| `RunnerTests/RunnerTests.swift` | Unit test target | Empty placeholder `testExample()` (no assertions). |

**Info.plist purpose strings (verbatim):**
- `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription`: "WakeGuard connects to your smart alarm clock to sync alarms, timers, time, and display settings."
- `NSCameraUsageDescription`: "WakeGuard uses the camera to verify your wake object and scan backup dismissal codes."
- `NSLocationAlwaysAndWhenInUseUsageDescription` / `NSLocationWhenInUseUsageDescription`: "Bluetooth scanning may require location permission to discover nearby alarm clocks." (`NSLocationAlways…` added to resolve rejection ITMS-90683.)

**Presence checks:**
- `Runner/PrivacyInfo.xcprivacy` — **ABSENT** (only third-party Pods carry privacy manifests).
- iOS `*.entitlements` — **ABSENT** (none anywhere under `ios/`; macOS Runner has entitlements, iOS does not).
- `Runner/GoogleService-Info.plist` — **ABSENT**.

**Background modes & audio session:** `UIBackgroundModes` is absent — no `audio`, `bluetooth-central`,
`processing`, or `fetch` declared. No `AVAudioSession` configured natively. The Dedicated-Clock / Phone-Alarm
foreground ring relies on Dart-side `audioplayers` (which sets `AVAudioSessionCategory.playback` from Dart per
CLAUDE.md) with the screen kept awake by `wakelock_plus`. There is a foreground-ring feature **with no iOS
background-audio mode declared** — recorded in §13.

**Android (secondary target):** application label **WakeGuard**; `applicationId`/`namespace`
**`com.smartblealarm.smart_ble_alarm`** (template default — differs from the iOS bundle id).
Permissions: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`, `ACCESS_FINE/COARSE_LOCATION`,
`CAMERA`, `INTERNET`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`. **Release build signs with the debug keystore** (TODO in
`android/app/build.gradle.kts`). Core-library desugaring on (JDK 17).

**Test inventory (`smart_ble_alarm/test/`):**
- `ble_framing_test.dart` — encoder/decoder: checksum framing, ESC-escaping (incl. cmd byte == ESC), partial-frame buffering, corrupted-checksum drop.
- `ble_payloads_test.dart` — uint32 BE; 9-byte 0x02 layout incl. volume clamp + snooze collapse; 0x06 bit-packing; weather signed temp + `weatherHidden()`; sleep schedule.
- `dedicated_clock_test.dart` — `buildAlarmToneWav()` valid RIFF/WAVE; `SettingsBloc.dedicatedClockEnabled` default/persist.
- `image_recognition_test.dart` — `matchesLabel` semantics; `Alarm` JSON round-trip + legacy decode; `syncHash` sensitivity; `syncStatusFor`; v2 envelope + v1 migration.
- `light_theme_text_color_test.dart` — light-theme foreground luminance regression guard.
- `ringing_dismissal_test.dart` — task-aware label/icon/instruction mapping.
- `wake_button_overflow_test.dart` — button accessibility overflow at 2× bold; 54pt base height.
- `widget_test.dart` — smoke test: `SmartAlarmApp` builds with simulated backend.

---

## 8. Production Feature Inventory

For each: entry points · key files · dependencies · platform APIs · background? · notifications? · permissions?

1. **Onboarding & pairing** — `onboarding_screen.dart`, `setup_screen.dart`, `main.dart` routing. Deps: `permission_handler`, `flutter_blue_plus`, `shared_preferences`. Perms: BLE scan/connect, location. Background: no. Notifications: no.
2. **BLE connection lifecycle** — `ble_bloc.dart`, `ble_repository_impl.dart`, `main_screen.dart` (resume/pause). Deps: `flutter_blue_plus`. On-demand, foreground-only, ≤3 auto-connect attempts. Background: no.
3. **Alarm CRUD** — `alarms_tab.dart`, `alarm_edit_screen.dart`, `alarm_bloc.dart`, `alarm.dart`. Deps: `shared_preferences`, `flutter_blue_plus`, `image_picker`. Perms: camera (item capture). 5-slot cap.
4. **Alarm sync to clock** — `clock_sync.dart`, `ble_payloads.dart`, `alarm_bloc.dart`, firmware. Deps: `flutter_blue_plus`. Background: no.
5. **Backup notifications** — `notification_service.dart`, `alarm_bloc.dart`. Deps: `flutter_local_notifications`, `timezone`, `flutter_timezone`. Notifications: yes. Perms: notifications + exact alarm. Background: OS scheduler.
6. **Wake challenge — QR** — `scanner_screen.dart`, `secure_key_datasource.dart`, `ringing_dismissal.dart`. Deps: `mobile_scanner`, `crypto`, `flutter_secure_storage`. Perms: camera.
7. **Wake challenge — object photo** — `item_scan_screen.dart`, `image_recognition_datasource.dart`. Deps: `image_picker`, `google_mlkit_image_labeling`. Perms: camera. 3-min backup gate.
8. **Backup-code print** — `clock_tab.dart` (only Print button), `print_qr_code.dart`, `secure_key_datasource.dart`. Deps: `printing`, `pdf`, `crypto`.
9. **Ringing dismissal (3 surfaces)** — `ringing_dismissal.dart`, `main_screen.dart`, `home_tab.dart`, `alarms_tab.dart`. Deps: `flutter_blue_plus`.
10. **Timers** — `create_timer_sheet.dart`, `countdown_timer_cubit.dart`, `alarms_tab.dart`, `home_tab.dart`. Deps: `flutter_blue_plus` (0x0A/0x0B). Firmware runs the timer; app mirrors it (cannot cancel hardware timer).
11. **Physical-clock display config** — `display_tab.dart`, `settings_bloc.dart`, `main_screen.dart` (0x06/0x0D pushes), `ble_payloads.dart`. Deps: `flutter_blue_plus`.
12. **Weather push** — `weather_datasource.dart`, `clock_sync.dart`, `main_screen.dart` (15-min timer). Deps: raw `dart:io HttpClient`. **Network egress** (ipapi.co + open-meteo). Perms: none (IP geolocation).
13. **Settings** — `settings_screen.dart`, `settings_bloc.dart`. Deps: `shared_preferences`. Includes destructive "Reset Local Data".
14. **Dismissal history** — `dismissal_history_screen.dart`, `dismissal_history_cubit.dart`. Deps: `shared_preferences`.
15. **Dev simulator** — `simulated_ble_repository_impl.dart`, `main.dart` (kDebugMode gate). Debug-only.
16. **Phone Alarm (companion) — Beta, off by default** — `settings_screen.dart` toggles (`phoneAlarmEnabled`, `phoneAlarmRequireCharging`), `settings_bloc.dart`. Ring engine staged (Phase 2 background = `alarm` pkg, not present).
17. **Dedicated Clock — Beta, off by default** — `dedicated_clock_screen.dart`, `main.dart` (top-precedence route), `alarm_sound.dart`, `ringing_dismissal.dart`. Deps: `audioplayers`, `wakelock_plus`. Foreground ring only. Background: no iOS background-audio mode.
18. **Theming / Liquid Glass** — `glass.dart`, `wake_widgets.dart`, `app_theme.dart`, `app_colors.dart`, `app_background.dart`.

---

## 9. Audit Surface Map

Complexity/effort are relative sizing to plan the audit — **not** correctness assessments.

| # | Subsystem | Key files | Dependencies | Complexity | Est. effort | Order |
|---|---|---|---|---|---|---|
| 1 | BLE wire protocol (framing + payloads + entity ↔ firmware) | `ble_framing.dart`, `ble_payloads.dart`, `alarm.dart`, `WakeGuardClock.ino` | flutter_blue_plus | High | High | 1 |
| 2 | Alarm lifecycle & persistence | `alarm_bloc.dart`, `alarm.dart` | shared_preferences, flutter_blue_plus | High | High | 2 |
| 3 | Dismissal / anti-cheat & crypto | `ringing_dismissal.dart`, `scanner_screen.dart`, `item_scan_screen.dart`, `secure_key_datasource.dart`, firmware `tryDismiss` | crypto, flutter_secure_storage, mobile_scanner, mlkit | High | High | 3 |
| 4 | BLE connection lifecycle | `ble_bloc.dart`, `ble_repository_impl.dart`, `main_screen.dart` | flutter_blue_plus | High | Med-High | 4 |
| 5 | Sync orchestration | `clock_sync.dart`, `main_screen.dart` | flutter_blue_plus, shared_preferences | Med-High | Med-High | 5 |
| 6 | Notification backups | `notification_service.dart`, `alarm_bloc.dart` | flutter_local_notifications, timezone | Med-High | Med-High | 6 |
| 7 | iOS release config | `Info.plist`, `project.pbxproj`, `Podfile.lock` | — | Med | Med (gating) | 7 |
| 8 | Dedicated Clock / Phone Alarm ring engine (Beta) | `dedicated_clock_screen.dart`, `alarm_sound.dart`, `settings_bloc.dart` | audioplayers, wakelock_plus | Med-High | Med | 8 |
| 9 | Settings + persistence | `settings_bloc.dart`, `settings_screen.dart`, `display_tab.dart` | shared_preferences | Med | Med | 9 |
| 10 | Firmware (autonomous clock) | `WakeGuardClock.ino` | Arduino/HM-10/ILI9341 | High | Med (needs HW) | 10 |
| 11 | Camera/ML datasources | `image_recognition_datasource.dart`, `scanner_screen.dart`, `item_scan_screen.dart` | mlkit, image_picker, mobile_scanner | Med | Med | 11 |
| 12 | Weather / network egress | `weather_datasource.dart`, `clock_sync.dart` | dart:io | Low-Med | Low | 12 |
| 13 | Timers | `create_timer_sheet.dart`, `countdown_timer_cubit.dart` | flutter_blue_plus | Low-Med | Low | 13 |
| 14 | UI shell / theming | `main_screen.dart`, theme files, tabs, widgets | — | Med | Low | 14 |
| 15 | **UI correctness & visual/aesthetic QA** (theme parity, overflow, layout, safe-area, Dynamic Type, glass rendering) | all `presentation/screens/**` + `tabs/**` + `widgets/**` + `core/theme/**` | — | High (broad, device-dependent) | Med-High (runtime, multi-device) | see §10a |

> **Note on "production-critical" in the file inventory (§3):** the ❌ marks mean *not functionally
> load-bearing* (a failure does not corrupt alarms/sync/dismissal). It does **not** mean "exempt from
> visual review." Every ❌ UI file is in scope for the aesthetic/visual QA pass described in §10a and the
> mandatory UI audit in §15.

### §9a — Per-subsystem UI audit objectives

For **every user-facing subsystem** the auditor must satisfy five UI objectives: **(F)** UI-functionality
verification, **(Q)** UI-quality (visual) verification, **(W)** expected user workflows exercised end-to-end,
**(V)** expected visual behavior confirmed, and **(M)** manual UI validation on-device. These extend (do not
replace) the engineering objectives in the §9 table.

| Subsystem (screens) | F — functionality to verify | Q — visual quality to verify | W — workflows | V — expected visual behavior | M — manual validation |
|---|---|---|---|---|---|
| **Onboarding** (`onboarding_screen.dart`) | Every page reachable; Next/Back/Skip/Get-Started act; dedicated-clock CTA routes; `hasSeenOnboarding` set once | Page spacing/typography consistent; hero art not clipped; footer buttons aligned; pager dots correct | Complete onboarding; skip onboarding; enter dedicated-clock setup from onboarding | Smooth page transitions; no overflow at any text size | Fresh install, light+dark, SE+iPad |
| **Pairing / Setup** (`setup_screen.dart`) | Permission prompts fire and gate correctly; scan starts; auto-connect to first "WG Clock"; Skip works; nearby/no-clock sections toggle | Status/action cards aligned; scanning spinner; no jitter as devices appear | Pair a clock; deny a permission then retry; skip pairing; connect-a-clock later | Live scan list renders; connected → routes to Main | Real BLE + denied-permission paths |
| **Alarm list + timers** (`alarms_tab.dart`) | Segmented control switches; enable toggle flips `0x80`; swipe-delete + Undo; tap→editor; FAB adds; timer stop | Cards uniform; ringing card error tint + "Ringing now" pill; segmented control aligned; long labels truncate | Enable/disable; delete+undo; open editor; create/stop timer | Toggle animates; delete slide + undo snackbar; ringing state unmistakable | Long labels, many alarms, ringing state |
| **Alarm editor** (`alarm_edit_screen.dart`) | Time wheel + AM/PM; day chips; label field; challenge method chips; object capture; snooze/volume/fade steppers/slider; Save validations | Section cards consistent; wheel selection band aligned; stepper/slider styling; chip states | Create; edit; configure QR; configure object (capture→label pick); set snooze/volume/fade; cancel | Save haptic; validation snackbars; keyboard avoidance on text fields | Camera capture + label picker; validation errors; large text |
| **Wake challenge — QR** (`scanner_screen.dart`) | Camera preview; detect→verify→`0x09`; invalid feedback; disconnected guard | Reticle/instruction cards centered; full-bleed preview; no letterboxing | Scan valid code → dismiss; scan invalid → error; scan while disconnected | Reticle overlay crisp; success haptic then pop | Real camera, real printed QR, low light |
| **Wake challenge — object** (`item_scan_screen.dart`) | Capture→label→match→`0x09`; 3-min backup gate countdown then bypass button | Countdown legible; detected-labels list; hint text; gate hidden when not this alarm's ring | Match object → dismiss; fail match; wait gate → backup QR | Live countdown ticks; match → pop | Real objects, gate timing, mismatch path |
| **Ringing dismissal** (`ringing_dismissal.dart` on 3 hosts) | Correct action per challenge on banner + Home card + Alarms card; no free dismiss | Label/icon/instruction identical across all 3 surfaces; error tinting consistent | Dismiss no-challenge; take photo; scan QR — from each surface | Three surfaces stay in sync; banner overlays without pushing content | Trigger ring, verify all 3 surfaces |
| **Timers** (`create_timer_sheet.dart`, `countdown_timer_cubit.dart`) | Wheel picker; validation; `0x0A` start; live countdown; `0x0B` stop | Sheet handle/grip; wheel band; countdown mono spacing | Create timer; let it run; stop timer | Sheet slides up; countdown updates each second | Disconnected guard, long durations |
| **Clock / Device** (`clock_tab.dart`) | Online/offline pill; Reconnect; Forget (confirm→route); sync panel counts; Print backup code | Header layout; sync stats aligned; print button placement | Reconnect; forget device; sync now; print backup code | Pill reflects state; sync spinner; print dialog opens | Real device online/offline, print |
| **Display config** (`display_tab.dart`) | Theme/accent/seconds/day/date-format/24h; sleep pickers; weather toggle+unit → BLE pushes | Swatch grid; chips; toggle rows uniform; date-format sample chips | Change each display option; set sleep window; toggle weather | Immediate push while connected; disabled hints when offline | Connected clock, visual push to hardware |
| **Settings** (`settings_screen.dart`) | Every row acts; theme/accent/background live; toggles persist; contextual advanced row (dev/unpair/connect); reset; About/Privacy/Licenses | Section grouping; row heights; destructive styling; background preview tiles | Change appearance/time/challenge/notifications/phone-alarm; reset; open dialogs | Theme/accent/background apply instantly app-wide | Every toggle round-trip; destructive confirms |
| **Dismissal history** (`dismissal_history_screen.dart`) | List renders; QR/Item pills; clear-all confirm | Empty state; row separators; pill colors; timestamps formatted | View history; clear history | Empty vs populated states | After several dismissals |
| **Dedicated Clock (Beta)** (`dedicated_clock_screen.dart`) | Minute detection→ring; snooze; dismiss via challenge; keeps awake; exit | Clock face legible far away; ring overlay; next-alarm pill; brightness | Fire alarm on spare device; snooze; dismiss | Face renders full-screen; ring overlay clear | Spare device overnight, silent switch |
| **App shell / theming** (`main_screen.dart`, `liquid_glass_tab_bar.dart`, `core/theme/**`) | Tab switching; banners overlay; status-bar overlay per screen | Glass blur; tab-bar float/pill; theme parity; safe-area | Navigate all tabs; background/resume; theme switch | No double status-bar inset; consistent glass | Light+dark, notch/Dynamic Island, iPad |

---

## 10. Manual Testing Targets

Features that exist and cannot be fully validated by static analysis. Each notes *why*.

1. **Alarm ringing on the physical clock (no phone)** — the autonomous firmware timekeeping/drift and EEPROM survival across power loss are runtime/hardware behaviors; static analysis cannot exercise `micros()` drift or EEPROM.
2. **BLE end-to-end sync** — HM-10 framing, 20-byte chunking, mutex serialization, and byte-for-byte app↔firmware agreement only manifest on real radios.
3. **Dismissal token round-trip** — `0x09` token `memcmp` on-device (wrong token keeps ringing); requires a real/simulated clock.
4. **QR scan dismissal** — camera + `mobile_scanner` decode of the printed PDF; camera hardware + print pipeline.
5. **Object-photo dismissal** — real-world ML Kit label accuracy against a chosen object varies by lighting/angle; not statically determinable.
6. **Notification delivery timing** — zoned scheduling, iOS `timeSensitive`, Android exact-alarm + Doze behavior; OS scheduler runtime only.
7. **Notification survival across device reboot** — Android boot receivers; iOS reschedule-on-launch semantics.
8. **Timezone change / DST** — phone sends local epoch (`ble_payloads.currentEpochSeconds`); firmware `TIMEZONE_OFFSET_SECONDS=0`; correctness under travel/DST needs live clock changes.
9. **Cold launch / warm launch / background resume** — `ReconnectEvent`/`ReleaseConnectionEvent` on lifecycle transitions; observer behavior is runtime.
10. **Permission prompts** — first-run BLE/location/camera/notification prompts and denial paths; OS dialogs.
11. **Dedicated Clock foreground ring (esp. iOS)** — ringing through the silent switch via `audioplayers` playback category, gradual-wake ramp, wakelock keeping the screen on; device audio hardware + Focus/DND.
12. **Silent mode / Focus modes / lock screen** — whether the foreground ring and time-sensitive notifications sound under Silent/DND; policy-driven, device only.
13. **Low power mode** — effect on BLE reconnect and exact alarms.
14. **App upgrade / persistence migration** — v1→v2 `saved_alarms` envelope migration on a real upgrade install.
15. **App termination behavior** — what rings when the app is force-closed (hardware clock still rings; Dedicated Clock does not — Phase 2 background engine absent).
16. **Audio playback lifecycle** — looping WAV start/stop/snooze/dismiss transitions; runtime audio session.
17. **Weather push** — live network fetch from ipapi.co/open-meteo and 0x0C render on the TFT; network + hardware.
18. **Buzzer output** — active-vs-passive buzzer question (firmware `BUZZER_IS_ACTIVE=1` makes volume/fade no-ops); hardware only (three BuzzerTest sketches exist for this).

### §10a — UI correctness & visual / aesthetic QA targets

These are **visual and layout bugs** — not functional failures. Static analysis and the existing unit
tests do not catch them; they require running the app across themes, devices, orientations, text sizes,
and data extremes and *looking*. The two existing tests cover only a sliver
(`light_theme_text_color_test.dart` = light-theme foreground luminance; `wake_button_overflow_test.dart`
= button growth at 2× bold) — everything below is otherwise unguarded.

**Theme & color**
- Light/dark parity on **every** screen. CLAUDE.md flags a recurring hazard ("white text in light mode = stale build"); verify no white-on-white / low-contrast text after a clean rebuild. Files: `app_theme.dart`, `app_colors.dart`, all screens.
- Accent-color application across the 4 accents (`AppColors.accentNames`) — gradients, pills, selected states, and the `onAccent` black/white luminance pick (`app_theme.dart`).
- Status-bar icon contrast per screen via the `AnnotatedRegion<SystemUiOverlayStyle>` in `main.dart:259-272` (dark icons on light backgrounds and vice-versa, including AppBar-less screens).

**Liquid Glass rendering**
- `GlassCard`/`GlassBackground` backdrop-blur artifacts, over-blur, or banding (`glass.dart`); animated backgrounds (aurora/mesh/waves) for color banding and jank (`app_background.dart`), including **reduced-motion** honoring.
- Floating `LiquidGlassTabBar` — overlap with scrollable content, bottom safe-area/home-indicator spacing, selection-pill animation (`liquid_glass_tab_bar.dart`).

**Overflow, truncation & long data**
- Long alarm **labels**, **item descriptions**, and **device names** on the alarm cards, ring banner, Home ring card, and Clock/Device rows — verify ellipsis/wrap, not RenderFlex overflow (`alarms_tab.dart`, `home_tab.dart`, `ringing_dismissal.dart`, `clock_tab.dart`, `wake_widgets.dart`).
- Empty/loading/error states: `WakeEmptyState`, sync spinner driven by `clockSyncInProgress`, "N of M synced" counts, dismissal-history empty state.

**Layout / device / orientation**
- Small (iPhone SE) vs large vs **iPad** (`TARGETED_DEVICE_FAMILY = "1,2"`) — the clock face, wheel pickers, and tab bar layout.
- **Landscape** on iPhone (Info.plist allows Landscape L/R) — does any screen break, or should orientation be locked? (`ios/Runner/Info.plist` `UISupportedInterfaceOrientations`.)
- Safe-area / notch / Dynamic Island / home-indicator insets; the **banner-overlay Stack fix** (PROJECT_LOG notes a prior doubled status-bar inset) is regression-prone — verify banners overlay without pushing content or double-insetting (`main_screen.dart`).

**Accessibility scaling**
- **Dynamic Type / large text** beyond 2× across all screens (only buttons are unit-tested). Cupertino wheel pickers (`alarm_edit_screen.dart` `_TimeWheelPicker`, `create_timer_sheet.dart` `_TimerWheelPicker`) selection-band alignment under scaling.

**Interaction polish**
- Non-queueing snackbars replace rather than stack (`app_snackbar.dart`); haptics fire on primary actions; keyboard-avoidance on the label/description `TextField`s in `alarm_edit_screen.dart`.
- Ringing visual consistency across the **3 surfaces** (banner / Home card / Alarms card error-tint + "Ringing now" pill) — same label/icon/instruction, no drift (`ringing_dismissal.dart` + the three hosts).

**Dedicated Clock face (Beta)**
- Legibility at a distance, brightness, and always-on burn-in considerations of `dedicated_clock_screen.dart` `_ClockFace`/`_RingOverlay`/`_NextAlarmPill`.

### §10b — Runtime UI validation matrix (mandatory)

Static analysis and unit tests cannot establish that the *interface* works and looks correct — the auditor
must **run the app on device/simulator** and validate the following. This matrix is required in addition to
§10 and §10a and feeds the §16 gate. Each item is a runtime pass the auditor must perform.

- **Every screen** — visit every surface in the §15.1 inventory; confirm each renders, is reachable, and has no runtime exception on entry/exit.
- **Every navigation path** — exercise every route, push/pop, tab switch, deep path (e.g. Settings → Device → print; Alarms → editor → object capture → label picker), and Back/swipe-back from each; confirm the nav stack and return location are correct.
- **Every user workflow** — run each workflow in §15.3 end-to-end, including cancellation and failure branches.
- **UI responsiveness** — scrolling, taps, wheel pickers, and transitions remain smooth (no jank/dropped frames) on a low-end supported device.
- **Theme switching** — flip System/Light/Dark at runtime and confirm the whole app re-themes live with no stale colors.
- **Dark Mode** — walk every screen in dark mode; confirm contrast and glass rendering (pairs with the light-mode luminance guard).
- **Rotation** — rotate every screen (iPhone allows Landscape L/R per Info.plist); confirm layout holds or that orientation is intentionally constrained.
- **Dynamic Type** — set text size to the largest accessibility step; walk every screen; confirm no clipping/overflow and that controls remain usable.
- **Accessibility** — VoiceOver sweep of key flows (create alarm, dismiss ring, settings); confirm focus order, labels, and touch targets.
- **Keyboard interaction** — focus every text field (alarm label, item description); confirm the keyboard does not cover the field, return/submit behaves, and dismissal works.
- **Background / resume UI behavior** — background then resume on each major screen; confirm UI reflects current state (BLE reconnect banner, ringing state, sync timestamp) after `ReconnectEvent`/`ReleaseConnectionEvent`.
- **Notification-driven UI** — trigger a backup notification and confirm what the UI shows on tap/launch is correct (noting the backup notification has no dismissal action by design).
- **Alarm UI while locked** — with the device locked, confirm the ringing/notification presentation and that the intended dismissal path is (or is not) reachable from the lock screen; confirm the Dedicated Clock foreground ring behavior when the screen is on but the app is not actively used.
- **Alarm UI while unlocked** — with the app foregrounded, confirm the ringing banner/card appears on all three surfaces and the correct challenge action launches.
- **Cold launch state** — kill and relaunch in each routing state (paired / skipped / needs-onboarding / dedicated-clock) and confirm the correct screen and restored data.
- **Warm launch state** — re-foreground after a while; confirm timers/next-alarm/sync labels are current.

---

## 11. Missing Documentation

Present: `CLAUDE.md`, `README.md`, `PROJECT_LOG.md`, `Smart BLE Alarm Specification.md`, `UI Design.md`,
`Audit 1 report.md`. Relative to this repository, the following appear **absent**:

- **Release checklist / TestFlight submission runbook** — CLAUDE.md §8 has scattered notes (build-number bump, export compliance, ITMS-90683 history) but there is no single pre-submission checklist.
- **Privacy manifest & App Privacy "nutrition label" doc** — no `PrivacyInfo.xcprivacy` and no documentation of data collection (camera, BLE, IP-geolocation weather) for App Store privacy answers.
- **Deployment / signing guide** — no doc of the iOS signing style/provisioning approach, nor the Android release-signing intent (currently debug-signed).
- **Alarm lifecycle diagram** — the lifecycle is described in prose across CLAUDE.md but there is no dedicated end-to-end lifecycle document (create→sync→ring→dismiss→auto-disable).
- **Notification lifecycle doc** — scheduling/delivery/reboot behavior is only implicit.
- **Dependency rationale doc** — no per-package "why + where" (this §6 fills that gap for the audit).
- **Firmware build/flash + version-compat doc** — CLAUDE.md notes firmware is "not compiled locally"; there is no record of which firmware build is on the reference hardware nor how it maps to app protocol revisions.
- **Test plan / manual QA matrix** — no documented manual test matrix (this §10 fills that gap).
- **Threat model for the dismissal contract** — the "one global static backup code" trade-off is noted in prose but not written up as a security model.

---

## 12. Questions the Auditor Should Answer

Items that cannot be determined from repository inspection alone (no guessing):

1. **Firmware ↔ app byte-compatibility on the reference hardware** — CLAUDE.md states the firmware was *not compiled locally* this session. Is the deployed clock running a build that reads the full 9-byte `0x02` frame and the 0x0C/0x0D commands?
2. **Current App Store Connect / TestFlight state** — what build number is already uploaded? `pubspec.yaml` shows `0.1.0+1`; has build 1 (or higher) been consumed, requiring a bump before the next upload?
3. **Export compliance** — `ITSAppUsesNonExemptEncryption` is absent from Info.plist. Is the intent to answer the prompt manually each upload (HMAC-only → exempt), or should the key be added?
4. **Privacy manifest** — is a `Runner/PrivacyInfo.xcprivacy` intended for this release, given camera, BLE, and IP-based geolocation (weather) data flows?
5. **iOS signing style** — Runner has no explicit `CODE_SIGN_STYLE`; is signing Automatic (managed) or Manual with a specific provisioning profile for distribution?
6. **audioplayers / wakelock_plus on iOS** — these are in `pubspec.lock` with darwin code but absent from `Podfile.lock`; are they linked via the Flutter SwiftPM package (`FlutterGeneratedPluginSwiftPackage`) and does a clean `flutter build ipa` reproduce a working binary? (Runtime/build question.)
7. **Submission scope** — is this an iOS-only App Store submission, or is Android also shipping (which would surface the debug-signing and applicationId-mismatch items)?
8. **Beta feature scope for this release** — are Phone Alarm and Dedicated Clock intended to be shipped/enabled in this build, or hidden Beta? Their reliability caveats (foreground-only, no iOS background audio mode) matter only if user-visible.
9. **Buzzer hardware** — is the shipped clock using an active or passive buzzer? Firmware `BUZZER_IS_ACTIVE=1` makes per-alarm volume/gradual-wake no-ops; is that the intended production config?
10. **Weather network egress acceptability** — are outbound calls to `ipapi.co` and `api.open-meteo.com` (with truncated lat/lon) acceptable for the privacy label and any regional requirements?
11. **Version-source truth for Android** — Android `applicationId` is the template default `com.smartblealarm.smart_ble_alarm` while iOS is `com.mekylealam.wakeguardalarm.a74sa4d686b`; is the divergence intentional?
12. **Reference-device pairing name** — the app matches `"WG Clock"` / service `FFE0`; is the production hardware advertising that exact name?

---

## 13. Potential Audit Targets

Recorded observations only — **not investigated, not judged, no fixes implied**. Grouped by area with `file:line`.

### Protocol / payloads / entity
- `ble_payloads.dart:22-25` — `currentEpochSeconds` transmits phone **local** wall-clock as the epoch (UTC + `timeZoneOffset.inSeconds`), not true UTC.
- `ble_payloads.dart:37-60` — `alarm()` throws `ArgumentError` on any field >255 (e.g. an `id ≥ 256` aborts payload build/sync).
- `alarm.dart:211-215` — `fromJson` casts `id/hour/minute/dayMask/qrRequired` with no null/type guard (throws on malformed persisted JSON).
- `ble_framing.dart` — XOR-checksum-only frame integrity; no CRC; 8-byte tokens; HM-10 is a transparent serial bridge with no link-layer pairing/encryption.
- `alarm_bloc.dart:433,462,532` — alarm ids masked to one byte (`& 0xFF`) on the wire (0x02/0x03/0x07); ids ≥256 or sharing a low byte are indistinguishable to hardware.
- `main_screen.dart:134-135` — inbound frame parsing trusts the frame's self-reported `len` (`frame.skip(2).take(len)`) with only a `frame.length < 2` guard.
- `main_screen.dart:141` — 0x08 ring-ack sends `0x88 [alarmId]` using the raw first data byte (not re-masked/validated).
- Magic-number 0x09 dismiss + payload framing duplicated across `scanner_screen.dart:64`, `item_scan_screen.dart:127-130`, `ringing_dismissal.dart:84`; timer bytes 0x0A/0x0B inline in `create_timer_sheet.dart:71-75` and `alarms_tab.dart:637-641`.

### Alarm bloc / persistence
- `alarm_bloc.dart:314,393` — `_onAddOrUpdateAlarm`/`_onDeleteAlarm` declared `void … async` while siblings are `Future<void>`; under `asyncExpand` the returned void is not awaited.
- `alarm_bloc.dart:236-255` — load decoders swallow every exception (`catch (_) {}`); corrupt persisted alarms/deletes/hashes load as empty with no signal.
- `alarm_bloc.dart:459-473` — `_onSyncAlarmsToDevice` early-returns on the first delete failure, leaving remaining pending deletes/alarms unsynced that pass.
- `alarm_bloc.dart:573-576` — backups rescheduled on every alarm change regardless of `backupNotificationsEnabled`; the gate lives inside `NotificationService`.

### Dismissal / crypto / anti-cheat
- `secure_key_datasource.dart:42-50` — `getDailyToken` is global/static (not daily, not per-alarm); `alarmId` ignored; one 8-byte token dismisses every protected alarm for the key's lifetime.
- `secure_key_datasource.dart:36` — `deleteKey` is a no-op; the key never rotates and is never cleared on alarm delete.
- `secure_key_datasource.dart:69-80` — hand-rolled `_constantTimeEquals` compares length-mismatched arrays by zero-padding.
- `secure_key_datasource.dart:7` — `FlutterSecureStorage` constructed with default options (no explicit iOS `KeychainAccessibility`).
- `ringing_dismissal.dart:84-87` — unsecured alarm dismissed by sending `0x09` with an all-zero token.
- `item_scan_screen.dart:44,167` — 3-minute backup bypass derives solely from `AlarmBloc.ringingSince`; hidden entirely if `ringingAlarmId != alarm.id`.
- `scanner_screen.dart:33-42,135` — no explicit camera-permission request before `MobileScanner` (relies on plugin).
- `print_qr_code.dart:14` — backup-code QR (base64 HMAC token) rendered to a PDF and sent to the system print pipeline (plaintext secret leaves the app on paper/spooler).
- Firmware `WakeGuardClock.ino:943-960` — `tryDismiss` accepts dismissal when an alarm is `qrRequired` but has **no stored token** (`ok = true`).

### BLE connection / sync
- `ble_bloc.dart:112-128` — real-device `AutoConnectEvent` emits `BleConnecting` and starts a scan without setting `_isConnecting` (only `DeviceFoundEvent` sets it).
- `ble_repository_impl.dart:82-87` — HM-10 service/characteristic matched by case-insensitive `contains("FFE0")/"FFE1"` substring, not exact UUID equality.
- `ble_repository_impl.dart:63` — `device.connect(license: License.nonprofit, …)` hard-coded.
- `ble_repository_impl.dart:159-170` — write path falls back to unacked `withoutResponse` writes (fixed 20 ms delay) when FFE1 lacks the write property (no delivery guarantee).
- `clock_sync.dart:169` — `catch (_)` swallows all sync-sequence exceptions; auto (non-user-initiated) syncs fail silently.
- `clock_sync.dart:86` — early `return false` when a sync is already in progress; a caller cannot distinguish "coalesced" from "failed".
- `clock_sync.dart:152-159` — `lastSyncEpochMs` persistence is fire-and-forget `unawaited`, no error handling.
- `countdown_timer_cubit.dart:113` — `removeTimer` cannot cancel the hardware timer (no firmware cancel command); a cleared timer keeps running on the clock.

### Notifications
- `notification_service.dart:34-40` — timezone resolution failure falls back to UTC (alarms scheduled at wrong wall-clock until resolved).
- `notification_service.dart:71,76` — scheduling silently skipped if `_ready` false; backup layer default-on (`?? true`).
- `notification_service.dart:134` — `_notificationId = alarmId*10 + weekday` assumes ids ≤255 / weekday ≤7 to avoid id collisions.

### Dedicated Clock (Beta)
- `dedicated_clock_screen.dart:107-122` — one-time alarm re-fires every day it stays enabled (no auto-disable in this mode); `_lastFiredKey` tracks only the most recent fire, so two alarms in the same minute ring only the first.
- `dedicated_clock_screen.dart:114,322` — weekday indexing uses `now.weekday % 7`; Sunday/Monday convention is load-bearing and unverified here.

### Startup / routing / lifecycle
- `main.dart:41` — `catch (_){}` on `notificationService.init()` silently discards notif/permission init failures at startup.
- `main.dart:102,118` — manual `previous.dispose()` on BLE backend swap is the only disposal path for the abandoned repository.
- `main.dart:132-136` — `_unpairDevice` sets `hasSeenOnboarding=false`, so unpair (with `setupSkipped` false) routes to `OnboardingScreen`, not `SetupScreen`.
- Raw pref-key string literals written inline: `settings_screen.dart:842-843` (`hasSeenOnboarding`), `clock_tab.dart:272-273` (`rememberedDeviceId`).

### Networking (weather)
- `weather_datasource.dart:43` — outbound IP-geolocation call to third-party `https://ipapi.co/json/` (no permission prompt; location leaves device).
- `weather_datasource.dart:57-63` — outbound call to `api.open-meteo.com` with lat/lon truncated to 3 decimals.
- `weather_datasource.dart:92-98` — raw `dart:io HttpClient`, no explicit TLS/cert-pinning config; non-200 silently → null.

### iOS / Android release config
- `ios/Runner/PrivacyInfo.xcprivacy` — **absent** (no app privacy manifest).
- `ios/Runner/Info.plist` — no `ITSAppUsesNonExemptEncryption` (export-compliance prompt unresolved).
- `ios/Runner/Info.plist` — no `UIBackgroundModes`; Dedicated-Clock/Phone-Alarm foreground ring (audioplayers + wakelock_plus) has no iOS background-audio/bluetooth-central mode declared.
- `ios/Runner.xcodeproj/project.pbxproj` — Runner target has no explicit `CODE_SIGN_STYLE`; `CODE_SIGN_IDENTITY = "iPhone Developer"` + team `HX7S7KAF9X`.
- `ios/Podfile.lock` — `audioplayers`/`audioplayers_darwin` and `wakelock_plus` absent from the pod list while present in `pubspec.lock` (SwiftPM/CocoaPods hybrid; lock may be out of sync with resolved plugins).
- `ios/RunnerTests/RunnerTests.swift:7` — placeholder test, no assertions.
- `pubspec.yaml:56,59` — `wakelock_plus`/`audioplayers` declared `^1.2.8`/`^6.1.0` but resolved to 1.6.1/6.8.1.
- `android/app/build.gradle.kts:32-38` — release build type signs with debug keys (TODO); no release signing config.
- `android/app/build.gradle.kts:23` — `applicationId` is template default `com.smartblealarm.smart_ble_alarm` vs iOS `com.mekylealam.wakeguardalarm.a74sa4d686b` (cross-platform identity mismatch).
- `build/ios/SourcePackages/workspace-state.json` — a build artifact tracked in git despite the root `.gitignore` `/build/` rule.

### Firmware
- `WakeGuardClock.ino:216-218` — `BUZZER_IS_ACTIVE` defaults to 1, making per-alarm `volume`/`gradualWakeSeconds` (0x02 wire bytes 7–8) no-ops on that hardware config.
- `WakeGuardClock.ino` — weather (0x0C) and sleep window (0x0D) are RAM-only (re-pushed every sync); a clock power-cycle loses both until the next sync.

### Assets
- `wake_widgets.dart:608-619` — `WakeLogoMark` depends on `assets/branding/wakeguard_logo.png` with a runtime `errorBuilder` fallback (the asset is declared in `pubspec.yaml:84` and tracked).

---

## 14. Recommended Audit Order

Ordered to front-load the load-bearing, hardest-to-reverse surfaces and the release gates.

1. **BLE wire protocol integrity** — `ble_framing.dart`, `ble_payloads.dart`, `alarm.dart`, and firmware `handleFrame`/decoder. Confirm the app and firmware agree on framing, checksum, the 9-byte `0x02` layout, and the length-guarded extension rule. (This is the single point where a byte error silently breaks the clock.)
2. **Alarm lifecycle & persistence** — `alarm_bloc.dart` + `alarm.dart`: sequential transformer, v2 envelope + v1 migration, 5-slot enforcement, `syncHash`, pending-delete/synced-hash bookkeeping, notification + BLE fan-out.
3. **Dismissal & anti-cheat contract** — `ringing_dismissal.dart`, `scanner_screen.dart`, `item_scan_screen.dart`, `secure_key_datasource.dart`, and firmware `tryDismiss`. The security-relevant path (token model, zero-token unsecured dismiss, 3-minute gate, no-stored-token acceptance).
4. **BLE connection lifecycle** — `ble_bloc.dart`, `ble_repository_impl.dart`, `main_screen.dart` resume/pause + inbound frame handling.
5. **Sync orchestration** — `clock_sync.dart` + the `main_screen.dart` setting-push listeners (0x06/0x0C/0x0D) and coalescing.
6. **Backup notifications** — `notification_service.dart` + `alarm_bloc._rescheduleBackupAlarms`: tz resolution, id scheme, iOS/Android scheduling, reboot survival.
7. **iOS release configuration (submission gate)** — `Info.plist` (purpose strings, missing `PrivacyInfo.xcprivacy` / `ITSAppUsesNonExemptEncryption` / `UIBackgroundModes`), `project.pbxproj` signing, `Podfile.lock` vs resolved plugins.
8. **Beta ring engines** — `dedicated_clock_screen.dart` + `alarm_sound.dart` + `settings_bloc.dart` phone-alarm/dedicated toggles (scope-dependent; only if shipping enabled).
9. **Settings & display config** — `settings_bloc.dart`, `settings_screen.dart`, `display_tab.dart`.
10. **Firmware review** — `WakeGuardClock.ino` (timekeeping/drift, EEPROM, ring engine, buzzer config) — pairs with #1/#3; may need hardware.
11. **Camera / ML datasources** — `image_recognition_datasource.dart` + the two scan screens.
12. **Weather / network egress** — `weather_datasource.dart` (privacy-label relevant).
13. **Timers** — `create_timer_sheet.dart`, `countdown_timer_cubit.dart`.
14. **UI shell & theming** — `main_screen.dart`, theme files, tabs, widgets (lowest production risk).

> **UI audit is not optional and not last.** The order above sequences the *engineering* review. The UI
> audit (§15) runs in parallel and is a **gating** requirement (§16): the auditor exercises the running
> application across every surface in §15.1 while reviewing the code. Engineering-order #14 ("lowest
> production risk") refers only to the risk of the UI *code* corrupting core data — it does **not** lower
> the priority of verifying that the UI *works and looks correct*, which is mandatory.

---

## 15. UI Audit Requirements

**This section is the definitive blueprint for auditing every user-facing aspect of the application.**
The subsequent auditor must perform a comprehensive audit of **every user-facing component** — every screen,
page, dialog, bottom sheet, popup, overlay, menu, navigation destination, onboarding screen, alarm workflow,
scanner interface, settings page, and any other visible interface. The UI audit covers **both UI
functionality and UI quality (aesthetics)** and carries equal weight to the engineering audit.

**Method.** The auditor must **exercise the running application** (device or simulator), not merely read
code. Every objective below is a verification the auditor performs and records. **The absence of a finding
is only valid if the surface was actually reached and exercised** — "not examined" must never be reported as
"no issue." No user-facing surface is out of scope.

### 15.1 UI Surface Inventory — audit every one

The complete set of user-facing surfaces. The auditor must **reach, exercise, and evaluate each**. This list
is a **floor, not a ceiling**: if a surface exists at runtime that is not listed, the auditor must add it and
audit it.

**Full-screen routes / pages**

| Surface | Type | File | Reached via |
|---|---|---|---|
| Onboarding carousel (multi-page + dedicated-clock page) | Screen | `onboarding_screen.dart` | First launch |
| Pairing / Setup | Screen | `setup_screen.dart` | After onboarding · Settings → Connect a Clock |
| Main tab shell | Shell | `main_screen.dart` | After pairing / skip |
| Home tab | Tab | `tabs/home_tab.dart` | Tab bar |
| Alarms tab (Alarm/Timer segmented) | Tab | `tabs/alarms_tab.dart` | Tab bar |
| Clock / Device (`ClockDeviceScreen`) | Tab/Screen | `tabs/clock_tab.dart` | Tab bar · Settings → Device |
| Settings (also usable as a tab) | Tab/Screen | `settings_screen.dart` | Tab bar |
| Display settings | Screen | `tabs/display_tab.dart` | Settings / Clock |
| Alarm editor (create/edit) | Screen | `alarm_edit_screen.dart` | Alarms FAB · tap card · Home quick action |
| QR scanner | Screen | `scanner_screen.dart` | Ring dismissal · backup gate |
| Item / object scan | Screen | `item_scan_screen.dart` | Ring dismissal |
| Dismissal history | Screen | `dismissal_history_screen.dart` | Settings → Data |
| Dedicated Clock (Beta) | Full-screen mode | `dedicated_clock_screen.dart` | Onboarding/pairing/Settings; boots straight in when enabled |

**Modals · sheets · overlays · dialogs · transient UI**

| Surface | Type | File / anchor |
|---|---|---|
| Create Timer | Bottom sheet | `create_timer_sheet.dart` (`showCreateTimerSheet`) |
| Wake-object label picker | Bottom sheet | `alarm_edit_screen.dart` `_showLabelPicker` |
| Sleep-window time pickers | Dialog | `display_tab.dart` `showTimePicker` |
| Ringing banner (over all tabs) | Overlay | `main_screen.dart` |
| Connectivity banner | Overlay | `main_screen.dart` |
| Home ringing card | Inline card | `home_tab.dart` `_ringingCard` |
| Alarms-card ringing state | Inline state | `alarms_tab.dart` |
| Swipe-to-delete + Undo | Gesture + snackbar | `alarms_tab.dart` (`Dismissible`) |
| Confirm: Unpair / Exit Developer Mode / Reset Local Data / Forget Device / Clear History / Replay Onboarding | Dialogs | `settings_screen.dart`, `clock_tab.dart`, `dismissal_history_screen.dart` |
| About / Privacy / Licenses | Dialogs / license page | `settings_screen.dart` |
| Snackbars (info / success / error) | Transient | `app_snackbar.dart` |
| Permission prompts (BLE / location / camera / notifications) | System | `setup_screen.dart`, plugins |

### 15.2 UI Functional Verification

For every surface (§15.1) and every workflow (§15.3), the auditor must verify that **every user-interface
element functions correctly**:

- Every screen can be reached through normal navigation.
- No unreachable screens exist.
- Navigation behaves correctly.
- Navigation stacks behave correctly.
- Deep navigation paths function correctly.
- Back navigation behaves correctly.
- Buttons perform their intended actions.
- Gestures behave correctly (swipe-to-delete, swipe-back, wheel scrolling, pull interactions).
- Toggles update the correct state.
- Sliders work correctly (e.g. volume).
- Pickers update values correctly (time wheels, day chips, date-format chips, timer wheels).
- Text fields accept, validate, and persist input correctly (alarm label, item description).
- Forms submit correctly (alarm editor save).
- Validation messages appear appropriately.
- Confirmation dialogs function correctly.
- Alert dialogs function correctly.
- Sheets open and dismiss correctly.
- Menus perform the intended actions.
- Context menus behave correctly.
- UI reflects the underlying application state.
- UI updates immediately after user actions.
- Error states display correctly.
- Empty states display correctly.
- Loading states behave correctly.
- Progress indicators behave correctly (sync spinner, scan progress).
- Disabled controls become enabled when appropriate (e.g. offline-gated actions).
- Success feedback appears when expected.
- Failure feedback appears when expected.
- Animations do not interfere with functionality.
- No controls appear visually interactive while being non-functional.
- No visible functionality is disconnected from application logic.

### 15.3 Workflow Verification

The auditor must verify **every complete user workflow** end-to-end. The workflows present in this app
include (at minimum):

- **Alarms:** create · edit · delete (swipe + undo) · enable · disable · configure recurrence (day mask) · configure wake challenge (QR vs object, incl. object capture + label pick) · configure snooze / volume / gradual-wake.
- **Ringing:** dismiss — no challenge · dismiss — QR scan · dismiss — object photo · gated backup-QR bypass (3-minute) · snooze (Dedicated Clock).
- **Camera scanning:** QR scan · object capture + on-device recognition.
- **Permission requests:** BLE scan/connect · location · camera · notifications (grant and denial paths).
- **Timers:** create · run · stop.
- **Backup code:** print from Clock tab.
- **Pairing / connectivity:** pair · skip pairing · reconnect · forget / unpair · enter/exit developer (simulated) mode · set up Dedicated Clock.
- **Settings changes:** theme / accent / app background · 24-hour · auto time-sync · default challenge · backup notifications · phone-alarm toggles · clock display + sleep + weather · reset local data · replay onboarding.
- **History:** view · clear.
- **Onboarding:** complete · skip.
- **Import/export:** *state whether present* — the auditor must confirm there is no import/export surface, or audit it if one exists.

For every workflow, verify that:

- Every step is reachable.
- Every step completes successfully.
- UI transitions occur correctly.
- Internal state remains consistent.
- Data is correctly persisted.
- Navigation returns the user to the correct location.
- Failure paths behave correctly.
- Cancellation behaves correctly.

### 15.4 UI State Verification

The auditor must inspect and confirm that **visible UI always reflects the underlying application state**:

- State synchronization (bloc/cubit state → widgets, and the global `ValueNotifier`s: `appBackgroundStyle`, `lastClockSync`, `clockSyncInProgress`).
- Widget rebuilding (correct `buildWhen`/`BlocBuilder` scopes; no stale or missing rebuilds).
- State restoration.
- State persistence (`shared_preferences` + secure storage round-trips reflected in UI).
- Lifecycle-driven UI updates.
- Background/resume updates (`ReconnectEvent` / `ReleaseConnectionEvent`).
- Cold launch state (correct routing + restored data per §4.3).
- Warm launch state (current timers, next-alarm, sync labels).

### 15.5 UI Bug Detection

The auditor must **actively search for** (record occurrences; do not fix):

- Broken buttons.
- Dead controls.
- Missing interactions.
- Incorrect navigation.
- Incorrect routing.
- UI logic bugs.
- Missing state updates.
- Incorrect state synchronization.
- Visual components disconnected from logic.
- Duplicate functionality.
- Missing confirmation dialogs.
- Incorrect validation.
- Incorrect error handling.
- Incorrect loading behavior.
- Runtime UI exceptions.
- Crashes triggered through the interface.
- Features that appear implemented but cannot actually be used.

### 15.6 UI Aesthetic Review

The auditor must evaluate overall UI **quality** across the whole app.

**Visual Consistency**
- Consistent spacing · padding · margins.
- Consistent typography · iconography.
- Consistent button styles · corner radii · elevation.
- Consistent color usage.
- Consistent animations · transitions.
(WakeGuard anchor: verify the Liquid Glass system — `glass.dart`, `wake_widgets.dart`, `app_theme.dart` — is applied uniformly and no screen uses ad-hoc containers.)

**Layout Quality**
- Alignment issues · misaligned controls · uneven spacing.
- Clipped content · overflow · unexpected whitespace · crowded layouts.
- Scroll behavior (iOS bounce; no Android glow).
- Safe-area handling (notch / Dynamic Island / home indicator; the banner-overlay Stack).
- Keyboard avoidance.
- Responsive layouts · large-screen (iPad) · small-screen (SE) · orientation handling.

**Platform Integration (modern iOS expectations, where applicable)**
- Native-feeling interactions.
- Appropriate navigation patterns.
- Appropriate modal presentation.
- Appropriate sheet behavior.
- Proper safe-area usage.
- Appropriate gesture behavior (swipe-back, sheet drag).
- Correct system-UI integration (status-bar overlay per screen via `AnnotatedRegion`).

**Accessibility Review**
- Dynamic Type compatibility (beyond 2×).
- VoiceOver compatibility.
- Touch-target sizing.
- Color-contrast concerns (light + dark).
- Focus order.
- Accessibility labels (where determinable from code).
- Reduced Motion compatibility (`AnimatedAppBackground` honoring `disableAnimations`).

---

## 16. Definition of Production Ready

This section defines the **gate**. The subsequent auditor **must not conclude that the application is
production-ready** (App Store submission) unless **all** of the following have been verified by actually
exercising the running application and reviewing the code — not by reading code alone, and not by leaving any
surface unexamined.

**UI functionality & experience (mandatory — added by this specification):**
- All UI functionality works correctly (§15.2 satisfied across every surface in §15.1).
- No significant UI bugs were identified (§15.5 swept; any found are recorded).
- User workflows complete successfully (§15.3 end-to-end, incl. cancellation + failure paths).
- Navigation is reliable (every path, stack, deep path, and back-navigation verified).
- UI state remains consistent (§15.4 — visible UI always reflects application state, including cold/warm launch and background/resume).
- The application provides a **polished, production-quality user experience appropriate for App Store
  release** (§15.6 — visual consistency, layout quality, iOS platform integration, and accessibility).
- The runtime UI validation matrix (§10b) has been performed on device (themes, rotation, Dynamic Type, accessibility, keyboard, lock-screen alarm UI).

**Engineering (from the existing specification — also required):**
- The BLE wire protocol is verified consistent app ↔ firmware (§14 #1).
- Alarm lifecycle & persistence, dismissal/anti-cheat, connection lifecycle, sync, and notification backups are verified (§14 #2–#6).
- iOS release configuration is resolved to the submitter's intent (§7, §12 — privacy manifest, export compliance, background modes, signing).
- The open questions in §12 have been answered by the submitter where they gate release.

**Reporting rule.** For each criterion the auditor must state that it was **verified** (with how it was
exercised) or **not met** (with the observed behavior recorded under the appropriate section). A criterion
that was not exercised is **not** "met" — it is "not verified," and blocks a production-ready conclusion.

---

*Prepared as a discovery/orientation artifact only. It performs no audit, recommends no fixes, and asserts
no correctness conclusions. All `file:line` references are to the `main` branch at commit `03824b1`. Where
this document and `agent reference/CLAUDE.md` agree they are mutually reinforcing; where the original
`Smart BLE Alarm Specification.md` conflicts with current code, the code and CLAUDE.md are authoritative.*
