# WakeGuard — Project Memory (CLAUDE.md)

> Companion Flutter app + Arduino clock firmware for a **wake-challenge alarm clock**.
> This file is the fresh-session brief. There is also a richer per-fact memory at
> `~/.claude/projects/-Users-aaron-development-Projects-Alarm-Clock/memory/` (see `MEMORY.md`
> index there) — read it for deep detail; this file is the fast overview.

## 1. Purpose & product
WakeGuard is a physical alarm clock (Arduino + HM-10 BLE + LCD + buzzer) whose alarms can
**only be dismissed by completing a wake challenge**: scanning a printed QR "backup code" or
photographing a target object (on-device ML). The **Flutter app is a companion** — it configures
the clock over BLE and mirrors alarms as local-notification backups. **The clock is autonomous**:
it keeps time, rings, and enforces dismissal on its own even with no phone connected.

## 2. Repo layout
```
/                         git root (origin: github.com/cowfollowdog/WakeGuard.git, branch main)
  smart_ble_alarm/        the Flutter app (all Dart lives here)
  arduino/
    WakeGuardClock/       the clock firmware (WakeGuardClock.ino) — MUST stay byte-compatible with Dart BLE
    BuzzerTest1_SteadyDC/  standalone buzzer diagnostics (active buzzer → beeps)
    BuzzerTest2_Tone/      tone() 2 kHz (passive piezo → sings; decisive code-vs-hardware test)
    BuzzerTest3_BitBang/   bit-bang ~1 kHz
  Smart BLE Alarm Specification.md, UI Design.md, Audit 1 report.md, README.md
```
Flutter code is clean-architecture layered under `smart_ble_alarm/lib/`:
- `core/` — `ble/` (`ble_payloads.dart`, `clock_sync.dart`), `theme/` (Liquid Glass design system:
  `glass.dart`, `wake_widgets.dart`, `app_theme.dart`, `app_colors.dart`), `ui/app_snackbar.dart`,
  `notifications/notification_service.dart`, `utils/alarm_time_utils.dart`.
- `data/` — `datasources/` (`ble_framing.dart`, `secure_key_datasource.dart`,
  `image_recognition_datasource.dart`), `repositories/` (`ble_repository_impl.dart` real,
  `simulated_ble_repository_impl.dart` dev simulator).
- `domain/` — `entities/alarm.dart`, `repositories/ble_repository.dart`, `usecases/print_qr_code.dart`.
- `presentation/` — `blocs/` (alarm_bloc, ble_bloc, settings_bloc, timer_cubit, history_cubit),
  `screens/` (main_screen + `tabs/` home/alarms/clock, setup, onboarding, alarm_edit, scanner,
  item_scan, settings, dismissal_history), `widgets/` (ringing_dismissal, liquid_glass_tab_bar, …).

## 3. Tech stack
- **Flutter**, Dart SDK `^3.12.0`. State mgmt: **flutter_bloc**. BLE: **flutter_blue_plus** (HM-10 UART).
- Persistence: **shared_preferences** (alarms, settings, flags), **flutter_secure_storage** (backup-code key).
- Wake challenge: **mobile_scanner** (QR), **google_mlkit_image_labeling** + **image_picker** (object photo),
  **crypto** (HMAC-SHA256 tokens), **printing**/**pdf** (print QR).
- Backup alarms: **flutter_local_notifications** + **timezone**/**flutter_timezone**.
- **permission_handler** for BLE/camera/location.
- Firmware: C++ Arduino (`WakeGuardClock.ino`) — HM-10 BLE serial, LCD, buzzer on **pin D9**.

## 4. BLE protocol (⚠️ app and firmware MUST agree byte-for-byte)
- Transport: **HM-10** module, service UUID `FFE0`, characteristic `FFE1`, single RX/TX characteristic,
  **20-byte MTU chunking**. Real repo serializes concurrent writes with a mutex (see `ble_repository_impl.dart`).
- **Framing** (`ble_framing.dart` ↔ firmware `sendFrame`/decoder): `SOF(0x5B '[') , body… , EOF(0x5D ']')`.
  `ESC = 0x5C`. Every body byte (cmd,len,data,checksum) is uniformly escaped if it equals SOF/EOF/ESC.
  Checksum = `cmd ^ len ^ data…`. **Max payload = 15 bytes.**
- **Command set** (app→clock unless noted):
  | Code | Name | Payload |
  |------|------|---------|
  | 0x01 | TIME_SYNC | uint32 local-epoch secs (UTC secs + tz offset — phone owns DST) |
  | 0x02 | ALARM_ADD (upsert) | **9 bytes**: `[id,hour,min,dayMask,qrRequired,snoozeCount,snoozeDur,volume,gradualWake]` |
  | 0x03 | ALARM_DEL | `[id]` |
  | 0x04 / 0x05 | SYNC_START / SYNC_END | (brackets a sync batch) |
  | 0x06 | SETTINGS (display) | `[flags,theme,accent]` — flags bit0=24h, bit1=seconds, bit2=date; theme 0=dark/1=light; accent 0..3 (amber/blue/green/violet). Length-guarded; firmware runtime-applies + persists. (Was auto-dim/sleep, removed when the backlight became hardwired.) |
  | 0x07 | QR_KEY (store token) | `[id, token×8]` — per-slot dismissal token |
  | 0x09 | DISMISS | `[id, token×8]` — clock `memcmp`s vs stored token (0-token OK if `!ringSecured`) |
  | 0x0A / 0x0B | TIMER_SET / TIMER_STOP | timer control |
  | 0x88 | RING_ACK (app→clock) | app confirms it saw 0x08 (stops rebroadcast) |
  - **Clock→app**: `0x08` NOTIFY_RING `[alarmId]` (rebroadcast until 0x88); `0x89` ACK_DISMISS (ring stopped);
    `0x81..0x87,0x8A,0x8B` are ACKs echoing the matching command; `0xFF` CMD_ERROR `[errcode]`.
- **0x02 is a length-guarded positional frame.** Firmware reads trailing bytes only under `len >=` guards;
  older firmware ignores extra trailing bytes. **Extend ONLY by a coordinated app+firmware change** (both
  sides + `Alarm.syncHash` fold) — never one side alone. Byte order and `_byte()` validation live in
  `BlePayloads.alarm`.

## 5. Alarm model (`domain/entities/alarm.dart`)
Fields: `id, hour, minute, dayMask, qrRequired, itemLabel?, itemDescription?, label?, snoozeEnabled,
snoozeMaxCount, snoozeDurationMinutes, volumePercent(1–100), gradualWakeSeconds`.
- `dayMask` bit 0x80 = **enabled**; bits 0–6 = Sun..Sat repeat days.
- `usesItemScan` = has non-empty `itemLabel` (→ photo challenge); else QR if `qrRequired`.
- **Wire getters** collapse app fields to firmware bytes: `wireSnoozeCount/Duration` (0 when snooze off),
  `wireVolume` (clamp 1–100), `wireGradualWake`. **`syncHash`** = FNV-1a over exactly the 8 wire-relevant
  bytes (NOT `Object.hash` — needs stable-across-runs). Persisted per alarm to detect "clock hasn't got this
  yet". Changing the fold re-marks every alarm out-of-sync once (harmless, re-sends). Label/item are excluded
  so cosmetic edits don't force re-sync. Hardware has **5 alarm slots** (`maxHardwareAlarms`).

## 6. How major systems work
- **Backup code / dismissal token** (`secure_key_datasource.dart`): **ONE global app-wide code** (as of
  2026-07-07). Single secure-storage key `alarm_key_global` + fixed HMAC payload → `getDailyToken`/
  `getQRCodeData` ignore `alarmId` and return the SAME 8-byte token for every alarm. `deleteKey` is a **no-op**
  (rotating would invalidate the shared code). On sync the app pushes this token to every protected slot via
  0x07; dismissal (0x09) passes `memcmp` for any alarm. **No firmware change was needed** for the global code —
  the clock just stores identical tokens per slot. `PrintQrCodeUseCase.execute()` (no arg) prints the single QR;
  the **only** Print button lives in the **Clock tab** Backup Code section. (Trade-off the user accepted: a
  leaked code dismisses any alarm; no per-alarm rotation.)
- **Ringing dismissal** (`widgets/ringing_dismissal.dart`): single source of truth for the ring action, keyed on
  challenge — `!qrRequired`→"Dismiss" (0x09 zero token), `usesItemScan`→"Take Photo" (`ItemScanScreen`),
  else "Scan QR" (`ScannerScreen`). Rendered on **3 surfaces**: global banner (`main_screen`), big Home card
  (`home_tab._ringingCard`), and the **Alarms-tab card** (swaps its toggle for the action button + error
  tint/border + "Ringing now" pill). `AlarmState.ringingAlarmId` (from clock 0x08) marks what's ringing;
  `ringingSince` gates the item-alarm backup-QR bypass to **3 min** after ring start. There is deliberately NO
  free "dismiss anyway".
- **Sync** (`core/ble/clock_sync.dart`): `syncConnectedClock(context, device, {showSuccess})` — coalesced via
  `clockSyncInProgress` ValueNotifier, ≤2 attempts w/ settle delay; success/failure card only when user-initiated,
  silent otherwise. Auto-syncs on connect and on any alarm change. `lastClockSync` ValueNotifier drives the UI.
- **AlarmBloc**: events processed **one-at-a-time** on purpose (sequential transformer) — concurrent handling
  clobbers sync/delete records. **Don't change the transformer.** Schedules local-notification backups for
  enabled alarms; notifications can't run scan/QR dismissal, they're just a safety net.
- **Home routing** (`main.dart`, 3-way, in precedence): (1) `rememberedDeviceId != null` → MainScreen (paired;
  passes `onUnpairDevice`, or `onExitDeveloperMode` for the simulator); (2) `setupSkipped` pref → MainScreen
  offline with `onConnectClock`; (3) else `hasSeenOnboarding ? SetupScreen : OnboardingScreen`. **Skip** on
  pairing is persisted + reversible via Settings → Advanced → "Connect a Clock".
- **BLE connection is on-demand**: foreground-only, no background BLE; bounded auto-connect retries on app open
  (not a perpetual loop). The clock runs alarms itself regardless.
- **Dev simulator**: `SimulatedBleRepositoryImpl` (debug "Enter developer mode") lets the connected UI be explored
  without hardware; `rememberedDeviceId == 'simulated_device'`.

## 7. Conventions
- **Liquid Glass design system**: build UI with `glass.dart` (`GlassCard`, `GlassBackground`) + `wake_widgets.dart`
  (`WakeSection`, `WakeSettingsRow`, `WakeStatusPill`, `WakePrimaryButton`, `WakeSecondaryButton`, `WakeEmptyState`),
  not ad-hoc containers. Fully theme-driven (light + dark). "White text in light mode" = **stale installed build**,
  rebuild before touching colours.
- **Time display**: always route through `AlarmTimeUtils.formatTime(is24Hour:)` so the 24h/AM-PM toggle stays consistent.
- **Settings vs per-alarm**: Settings screen = universal prefs only; wake-challenge (QR/item/object) is per-alarm in
  the editor; the backup code is one global thing in the Clock tab.
- Snackbars: use `core/ui/app_snackbar.dart` `showAppSnackBar` (clears the queue first — no stacking/queue lag).

## 8. iOS / TestFlight
- Bundle ID **`com.aaronhua.wakeguard`** (RunnerTests `.RunnerTests`); `DEVELOPMENT_TEAM = HX7S7KAF9X`.
- Version in `pubspec.yaml` `version: 0.1.0+N` → `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`.
  **Bump the build number (+2, +3…) on every TestFlight upload** — App Store Connect rejects a reused build number.
- `Info.plist` purpose strings present: Bluetooth Always/Peripheral, Camera, Location WhenInUse **and**
  `NSLocationAlwaysAndWhenInUseUsageDescription` (added to fix rejection **ITMS-90683** — a bundled SDK needs it).
- **Export compliance**: app uses only HMAC (authentication) → standard/exempt; answer the encryption question with
  the exemption. (Optionally add `ITSAppUsesNonExemptEncryption=false` to Info.plist to skip the prompt — not yet added.)
- Build: `flutter build ipa` then upload via Transporter / Xcode Organizer.
- Plugin note (harmless warning): `google_mlkit_image_labeling`/`_commons` don't support Swift Package Manager yet.

## 9. Build / run / test
```
cd smart_ble_alarm
flutter pub get
flutter analyze                 # keep clean
flutter test                    # 39 tests currently pass
flutter run                     # device/simulator
flutter build ipa               # TestFlight
```
Tests live in `smart_ble_alarm/test/` (`ble_framing_test`, `ble_payloads_test`, `image_recognition_test`,
`light_theme_text_color_test`, `ringing_dismissal_test`, `widget_test`). No test pins the backup-code/print
internals, so those are safe to evolve; **`ble_framing`/`ble_payloads` tests guard the wire format — respect them.**
Arduino: open the relevant `arduino/*/*.ino` in Arduino IDE, select the board, upload. Buzzer is on **D9**
(active buzzer beeps on steady DC; passive piezo needs `tone()`), diagnosable with the three `BuzzerTest*` sketches.

## 10. Current status
- **First beta** (0.1.0). Core flows implemented: pairing/onboarding/skip, alarms CRUD + 5-slot sync, timers,
  clock display settings, QR + object-photo wake challenges, global backup code (print from Clock tab),
  3-surface ringing dismissal, backup notifications, dismissal history, Liquid Glass theming, dev simulator.
- Recently landed this session: **one global backup code** + Clock-tab-only print button (removed per-card/editor
  print + the pointless backup **scanner** button); **ringing state now shows prominently on the Alarms-tab card**.
- Also uncommitted/recent: banner-overlay fix (banners overlay content via Stack, don't extend past the status bar),
  Skip-pairing + Connect-a-Clock.
- **Known hardware issue under investigation**: buzzer produced no sound after reflash + cleaning; firmware verified
  correct, so it points to hardware (active-vs-passive mismatch or wiring). Awaiting the 3 BuzzerTest results.

## 11. Do NOT change without understanding first
- The **0x02 alarm frame** byte layout / length or **`Alarm.syncHash`** fold — coordinated app+firmware change only.
- **`ble_framing.dart`** SOF/EOF/ESC/checksum + 15-byte cap (matched exactly by firmware).
- **AlarmBloc sequential transformer** (concurrency would clobber sync/delete state).
- The **global backup-code model** (`alarm_key_global`, no-op `deleteKey`) — reverting to per-alarm keys breaks the
  "one code for all alarms" contract and the printed codes.
- **On-demand / foreground-only BLE** design — the clock is autonomous; don't add background BLE or a perpetual
  reconnect loop.
- **BLE name** the app pairs with is "WG Clock".
