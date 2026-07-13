# WakeGuard — Smart Alarm

WakeGuard is a companion mobile app for an **autonomous Bluetooth alarm clock** built to help people
with narcolepsy (and other conditions that make waking difficult) actually get out of bed. Unlike a
normal alarm that a single tap can silence, a WakeGuard alarm keeps sounding until the user physically
completes a **wake challenge** — reducing the chance of falling straight back asleep.

The full product has two halves, both in this repo:

| Component | Role | Location |
| --- | --- | --- |
| **Mobile app** (Flutter) | Configure alarms/timers, sync the clock over BLE, run the wake challenge to dismiss | [`smart_ble_alarm/`](smart_ble_alarm/) |
| **Clock firmware** (Arduino + HM-10 BLE) | Keeps time standalone, stores alarms/tokens, drives the LCD + buzzer | [`arduino/WakeGuardClock/`](arduino/WakeGuardClock/) |

Once the clock has been synced, it runs **independently of the phone**: it keeps time and fires alarms
on its own even with no phone connected. The phone is only needed to change configuration and to run the
wake challenge that dismisses a ringing alarm.

## How dismissal works

When an alarm fires the buzzer sounds until the wake challenge is completed. Each alarm chooses one of
three dismissal modes (see [`ringing_dismissal.dart`](smart_ble_alarm/lib/presentation/widgets/ringing_dismissal.dart)):

- **No challenge** (`!qrRequired`) — a plain **Dismiss** button silences the clock (sends `0x09` with a
  zero token, which the clock accepts for unsecured alarms).
- **Object photo / item scan** (`usesItemScan`) — **Take Photo** of a real-world object chosen when the
  alarm was created (e.g. a toothbrush). The app recognises it **on-device** with Google ML Kit image
  labeling (no network); a saved text description reminds the user what to find.
- **QR backup code** (`qrRequired`, no item) — **Scan QR** of the printed backup code.

The **backup code** is a single, app-wide printed QR that works for **every** protected alarm. It is an
8-byte HMAC-SHA256 token held in secure storage; it is intentionally **static** so a printed paper code
stays valid indefinitely. Because the code lives on paper away from the bed, scanning it forces the user
up and about. You print it once from **Clock tab → Backup Code**. For item alarms, the printed code is a
gated fallback that unlocks only **3 minutes** after the alarm starts ringing — there is deliberately no
free "dismiss anyway".

The ringing dismissal action appears on **three surfaces** so it's always reachable: a global banner over
every tab, the big Home ring card, and the Alarms-tab card (which turns red and shows a "Ringing now" pill).

## Architecture

The app follows a clean-architecture layout under [`smart_ble_alarm/lib/`](smart_ble_alarm/lib/), with
`flutter_bloc` for state management and a "Liquid Glass" design system (light + dark):

```
lib/
├── core/            # cross-cutting helpers
│   ├── ble/         # BLE payload builders + clock sync (ble_payloads.dart, clock_sync.dart)
│   ├── theme/       # Liquid Glass design system (glass.dart, wake_widgets.dart, app_theme/colors)
│   ├── ui/          # app_snackbar (non-queueing snackbars)
│   ├── notifications/ # local-notification backup scheduler
│   └── utils/       # alarm time / next-occurrence logic
├── data/
│   ├── datasources/ # BLE framing, secure token storage, on-device image recognition
│   └── repositories/# real (flutter_blue_plus) + simulated BLE repositories
├── domain/
│   ├── entities/    # Alarm
│   ├── repositories/# BleRepository interface
│   └── usecases/    # print QR backup code
└── presentation/
    ├── blocs/       # ble_bloc, alarm_bloc, settings_bloc, timer_cubit, history_cubit
    ├── screens/     # setup, onboarding, main (Home/Alarms/Clock/Settings tabs), edit, scanner, item_scan, history
    └── widgets/     # ringing_dismissal, liquid_glass_tab_bar, create_timer_sheet
```

A **simulated BLE repository** (`SimulatedBleRepositoryImpl`, device id `simulated_device`) lets the app
run end-to-end with no hardware — enter "developer mode" from the pairing screen (debug builds) to explore
the connected UI, sync, and dismissal without a physical clock.

## BLE protocol

The phone talks to the HM-10 module (service `FFE0`, characteristic `FFE1`, single RX/TX characteristic)
using a framed byte protocol ([`ble_framing.dart`](smart_ble_alarm/lib/data/datasources/ble_framing.dart)),
matched byte-for-byte by the firmware:

```
[ SOF(0x5B '[') | cmd | len | payload… (escaped) | checksum (XOR) | EOF(0x5D ']') ]
```

Every body byte (cmd, len, payload, checksum) that equals SOF/EOF/ESC(`0x5C`) is escaped with ESC; frames
are sent in ≤20-byte MTU chunks and concurrent writes are serialized with a mutex. **Max payload = 15 bytes.**
Command set:

| Cmd | Meaning | Payload |
| --- | --- | --- |
| `0x01` | Time sync | local-epoch seconds (uint32; UTC secs + tz offset, so the phone owns DST) |
| `0x02` | Add/update alarm (upsert) | `[id, hour, minute, dayMask, qrRequired, snoozeCount, snoozeDuration, volume, gradualWake]` (9 bytes) |
| `0x03` | Delete alarm | `[id]` |
| `0x04` / `0x05` | Sync start / end | — (brackets a sync batch) |
| `0x06` | Settings write | `[autoDim, sleepStartH, sleepStartM, sleepEndH, sleepEndM]` |
| `0x07` | Store dismissal token | `[id, 8-byte token]` (pushed to each protected slot) |
| `0x09` | Dismiss alarm | `[id, 8-byte token]` (clock `memcmp`s vs stored token; zero token OK if unsecured) |
| `0x0A` / `0x0B` | Timer set / stop | duration seconds (uint32) / — |
| `0x88` | Ring receipt (app → clock) | app confirms it saw `0x08`, stopping rebroadcast |

Clock → app frames: `0x08` alarm-triggered `[id]` (rebroadcast until `0x88`); `0x89` dismiss ack (ring
stopped); `0x81`–`0x87`, `0x8A`, `0x8B` are ACKs echoing the matching command; `0xFF` error `[code]`.

`dayMask` uses bit 7 (`0x80`) as the enabled flag and bits 0–6 as repeat days (bit 0 = Sun … bit 6 = Sat);
a repeat mask of 0 means a one-time alarm. The clock supports up to **5 alarms**. The `0x02` frame is a
length-guarded positional frame: the firmware reads each trailing byte only under a `len >=` guard, so it
stays backward-compatible — but its layout must only ever be extended by a **coordinated app + firmware
change** (both sides plus the `Alarm.syncHash` fold).

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.12`).

```bash
cd smart_ble_alarm
flutter pub get
flutter run           # run on a connected device/emulator
flutter analyze       # static analysis (keep clean)
flutter test          # unit + widget tests
flutter build ipa     # iOS / TestFlight build
```

On first launch the app shows onboarding, then the pairing screen. You can **Skip** pairing (persisted;
the app runs offline with alarms saved locally + mirrored to backup notifications, and re-pairing is
available under **Settings → Advanced → Connect a Clock**), or enter the built-in simulated clock in debug
builds.

The firmware lives in [`arduino/WakeGuardClock/`](arduino/WakeGuardClock/) — open it in the Arduino IDE,
select the board, and upload. The buzzer is on **pin D9**; three standalone `arduino/BuzzerTest*` sketches
isolate active-vs-passive-vs-wiring buzzer issues.

### Permissions

The app requests Bluetooth scan/connect and location permissions (Android BLE scanning requirement, and
iOS purpose strings including `NSLocationAlwaysAndWhenInUseUsageDescription`), camera permission for the QR
and object scans, and notification permission for backup alarms.

## Project docs

- [`CLAUDE.md`](agent%20reference/CLAUDE.md) — fresh-session engineering brief (architecture, protocol, conventions, status)
- [`PROJECT_LOG.md`](PROJECT_LOG.md) — attribution + full log of features and implementations
- [`Smart BLE Alarm Specification.md`](agent%20reference/Smart%20BLE%20Alarm%20Specification.md) — full hardware/app spec
- [`UI Design.md`](agent%20reference/UI%20Design.md) — UI & navigation spec
- [`Audit 1 report.md`](agent%20reference/Audit%201%20report.md) — earlier integration audit (issues since resolved)

Where these conflict, `CLAUDE.md`, this README, and the current code are the source of truth.
