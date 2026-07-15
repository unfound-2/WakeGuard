# WakeGuard — Feature List

A structured catalogue of what the WakeGuard app and clock actually do, grouped by area. Every entry is
backed by code in [`smart_ble_alarm/lib/`](../smart_ble_alarm/lib/) or
[`arduino/WakeGuardClock/`](../arduino/WakeGuardClock/).

## Alarms

- **Up to 5 hardware alarms** synced to the clock (`MAX_ALARMS` firmware-side, `maxHardwareAlarms` app-side).
- **Recurring by weekday** — a 7-bit day mask (bit 0 = Sun … bit 6 = Sat) repeats an alarm on chosen days.
- **One-time alarms** — an empty repeat mask fires once, then auto-disables on both app and clock.
- **Per-alarm enable flag** — day-mask bit 7 (`0x80`) arms/disarms without deleting the alarm.
- **Snooze allowance** — enable snooze and cap the number of snoozes per ring (`snoozeMaxCount`).
- **Snooze duration** — per-alarm snooze length in minutes (byte 6 of the `0x02` frame).
- **Gradual wake — ring volume** — per-alarm loudness 1–100% (byte 7), mapped to the clock's PWM duty.
- **Gradual wake — fade-in** — ramp the volume from a soft floor up to target over N seconds (byte 8).
- **Human-friendly label** — an optional name ("Wake up", "Meds"); phone-side only, never sent over BLE.
- **Deterministic sync hash** — `Alarm.syncHash` (FNV-1a over the wire bytes) detects which alarms the
  clock hasn't received yet, so only changed alarms re-send.

## Wake challenges (dismissal)

- **Plain dismiss** — unsecured alarms stop with a single Dismiss button (`0x09` with a zero token).
- **QR backup-code scan** — secured alarms are dismissed by scanning a printed QR (via `mobile_scanner`).
- **Object / item scan** — dismiss by photographing a chosen real-world object, recognised **on-device**
  with Google ML Kit image labeling (`google_mlkit_image_labeling`, no network).
- **Single global backup code** — one app-wide 8-byte HMAC-SHA256 token (secure storage) unlocks every
  protected alarm; intentionally static so the printed paper code stays valid indefinitely.
- **Printable backup code** — generated as a PDF/QR from the Clock tab (`print_qr_code` use case, `pdf`/`printing`).
- **Gated fallback for item alarms** — the printed code only unlocks 3 minutes after ring start; no free
  "dismiss anyway".
- **Three dismissal surfaces** — a global banner, the Home ring card, and the Alarms-tab card (which
  tints red with a "Ringing now" pill) all expose the dismissal action.
- **Token-gated hardware enforcement** — the clock keeps ringing until a matching token (or a valid app
  dismiss) arrives; a physical snooze button can snooze a secured alarm but not fully dismiss it.
- **Dismissal history** — a log of past dismissals (`dismissal_history` feature).

## Alarm templates

- **Ready-made routines** — Workday (Mon–Fri 07:00), Medication (daily 08:00), School (weekdays 06:30),
  and Weekend (Sat–Sun); tapping one pre-fills the alarm editor to fine-tune before saving.
- **Reached from the Alarms tab** via the "+" FAB → Templates screen.

## Timers

- **Countdown timer** — set a duration; the clock runs it autonomously and chimes a distinct "ding-dong"
  pattern when it finishes (`0x0A` set, `0x0B` stop).
- **Auto-silence** — a finished-timer chime self-silences after a timeout; a ringing alarm always wins
  the speaker.
- **Live countdown on the clock face** — the running timer shows on the info line.

## Standalone phone ring modes (serverless)

- **Dedicated Clock mode** — turn a spare phone into a standby bedside clock: the app boots straight into
  a full-screen clock face, keeps the screen awake (`wakelock_plus`), and rings in the morning while it
  stays open on a charger (top-precedence route in `main.dart`).
- **Phone Alarm companion mode** — the primary phone acts as a foreground backup ringer that fires the
  alarm itself and runs the wake challenge, so an alarm still goes off without the hardware clock.
- **Runtime-synthesized alarm tone** — looped via `audioplayers` when a phone ring mode sounds in the
  foreground.

## Display, themes & night mode

- **Clock face themes** — dark or light, pushed to the clock over `0x06`.
- **Accent presets** — amber, blue, green, violet (index 0–3), mirrored on both app and clock.
- **Clock-face content toggles** — show/hide seconds, calendar date, and day-of-week on the clock.
- **Date format** — four formats (`MMM D`, `D MMM`, `MM/DD/YY`, `YYYY-MM-DD`).
- **12/24-hour time** — a single toggle drives both the app and the clock face (routed through
  `AlarmTimeUtils.formatTime`).
- **App "Liquid Glass" theme** — shared glass design system with light + dark and selectable app
  background styles (a global `appBackgroundStyle` notifier).
- **Scheduled display sleep** — a nightly window (`0x0D`) blanks the clock panel with the ILI9341
  display-off opcode so a dark room stays dark; a ring always re-lights it. The backlight LED is hardwired
  to 3.3 V, so a faint glow remains (it can't truly switch off).
- **Animations toggle** — enable/disable app UI animations.

## Weather

- **Phone-pushed weather** — the clock has no network, so the phone fetches conditions and pushes them
  over `0x0C`; the clock draws a compact condition icon + temperature in a corner.
- **Condition buckets** — clear, partly cloudy, cloudy, rain, snow, thunder, fog (WMO codes mapped down
  app-side so the firmware icon set stays tiny).
- **Unit choice** — °C or °F (the app converts before sending; the clock is unit-agnostic).
- **Show/hide** — turning weather off pushes a hide frame (`0x0C [0, 0xFF]`) that blanks the corner.
- **RAM-only** — weather is not persisted on the clock; it's re-pushed on connect and periodically.

## BLE connectivity & sync

- **On-demand, foreground-only BLE** — the Arduino is autonomous; the app connects to sync, not to hold a
  perpetual/background session.
- **Auto-sync on connect** — connecting pushes time, alarms, tokens, display settings, sleep schedule, and
  weather; syncs are coalesced (`clockSyncInProgress`) to avoid overlap.
- **Batched sync framing** — `0x04`/`0x05` bracket a sync so the clock commits alarm changes to EEPROM in
  one write and holds display rendering to avoid dropping frames.
- **Auto time sync** — time is pushed as the phone's local epoch, so the clock matches the phone including
  DST (toggleable).
- **Simulated clock** — a built-in simulated BLE repository runs the whole flow (sync, ring, dismiss) with
  no hardware, for debug builds / developer mode.
- **Skip pairing & re-pair** — pairing can be skipped (persisted) and re-enabled later from Settings.

## Backup & reliability

- **Notification backup alarms** — enabled alarms are mirrored to local notifications (`flutter_local_notifications`,
  `timezone`) as a backup layer scheduled from the alarm bloc (can't run scan/QR dismissal, but still wakes you).
- **Evening reminder** — an optional nightly reminder notification.
- **Clock autonomy** — the clock keeps time, alarms, and dismissal tokens in EEPROM and fires with no
  phone present.
- **Oscillator drift correction** — the clock measures its resonator drift between time syncs and
  corrects the software clock (persisted `driftPPM`).
- **Display self-heal** — the idle clock face periodically re-inits the panel so a silently-corrupted
  (white) display recovers without a power cycle.
- **Hardware watchdog** — an ~8 s AVR watchdog reboots and re-inits everything if `loop()` ever wedges.
- **Boot self-test chime** — a power-on frequency sweep proves the speaker + PWM path works before any sync.

## Account & cloud (Firebase)

- **Sign-in** — Google Sign-In and Sign in with Apple (`google_sign_in`, `sign_in_with_apple`,
  `firebase_auth`).
- **Cloud alarm sync** — alarms sync to Firestore (`alarm_cloud_sync_service`) with an account profile editor.
- **Analytics & crash reporting** — Firebase Analytics and Crashlytics.

## Settings (universal preferences)

- 12/24-hour time, default "require wake challenge" for new alarms, app theme + accent, animations,
  auto time sync, backup notifications, evening reminder, clock display customization, clock sleep window,
  weather show/unit, Phone Alarm mode, Dedicated Clock mode, app background style, and re-pair a clock.
- Per-alarm wake-challenge / QR / item-scan config lives on the alarm itself; the backup code is one
  global code printed from the Clock tab (not per-alarm).
</content>
