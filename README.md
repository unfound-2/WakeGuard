# WakeGuard — Smart BLE Alarm

WakeGuard is a companion mobile app for an **autonomous Bluetooth alarm clock** built to help people
with narcolepsy (and other conditions that make waking difficult) actually get out of bed. Unlike a
normal alarm that a single tap can silence, a WakeGuard alarm keeps sounding until the user physically
leaves bed and completes a **dismissal task** — reducing the chance of falling straight back asleep.

The full product has two halves:

| Component | Role | Location |
| --- | --- | --- |
| **Mobile app** (Flutter) | Configure alarms, sync the clock over BLE, dismiss ringing alarms | This repo — [`smart_ble_alarm/`](smart_ble_alarm/) |
| **Alarm-clock firmware** (Arduino Uno R3 + HM-10 BLE) | Keeps time standalone, stores alarms, drives the buzzer | Separate — *not in this repo* |

Once the clock has been synced, it runs **independently of the phone**: it keeps time and fires alarms
on its own. The phone is only needed to change configuration and to dismiss a ringing alarm.

## How dismissal works

When an alarm fires, the buzzer sounds until the user completes a dismissal task in the app:

- **QR-code scan** — the user scans a printed QR code (generated and printed from the app). The token
  is an 8-byte HMAC-SHA256 of the alarm ID, keyed by a per-alarm 128-bit secret held in secure storage.
  It is intentionally **static** so a printed paper code stays valid indefinitely.
- **Item scan** — photograph a real-world object chosen when the alarm was created (e.g. a toothbrush).
  The app recognises it **on-device** with Google ML Kit image labeling (no network), and a saved text
  description reminds the user what to find. Item alarms still carry a hardware token, so the clock
  enforces the same secured dismissal as QR alarms — the recognition is a phone-side gate.

Because the QR code lives on paper away from the bed, dismissing the alarm forces the user up and about.

## Architecture

The app follows a clean-architecture layout under [`smart_ble_alarm/lib/`](smart_ble_alarm/lib/), with
`flutter_bloc` for state management:

```
lib/
├── core/            # cross-cutting helpers
│   ├── ble/         # BLE payload builders (ble_payloads.dart)
│   ├── theme/       # colors + Material 3 theme (Inter via google_fonts)
│   └── utils/       # alarm time / next-occurrence logic
├── data/
│   ├── datasources/ # BLE framing, secure QR-key storage
│   └── repositories/# real (flutter_blue_plus) + simulated BLE repositories
├── domain/
│   ├── entities/    # Alarm
│   ├── repositories/# BleRepository interface
│   └── usecases/    # clock sync, QR printing
└── presentation/
    ├── blocs/       # ble_bloc, alarm_bloc, settings_bloc
    └── screens/     # setup, main (Home/Alarms/Clock/Settings tabs), edit, scanner
```

A **simulated BLE repository** lets the app run end-to-end with no hardware — pair the virtual
`Smart Clock (SIM)` device to try alarms, sync, and dismissal in a simulator or on-device.

## BLE protocol

The phone talks to the HM-10 module (service `FFE0`, characteristic `FFE1`) using a framed byte protocol
([`ble_framing.dart`](smart_ble_alarm/lib/data/datasources/ble_framing.dart)):

```
[ SOF(0x5B) | cmd | len | payload… (escaped) | checksum (XOR) | EOF(0x5D) ]
```

Bytes equal to SOF/EOF/ESC in the payload are escaped with ESC (`0x5C`); frames are sent in ≤20-byte
MTU chunks. Command set:

| Cmd | Meaning | Payload |
| --- | --- | --- |
| `0x01` | Time sync | epoch seconds (uint32, big-endian) |
| `0x02` | Add/update alarm | `[id, hour, minute, dayMask, qrRequired]` |
| `0x03` | Delete alarm | `[id]` |
| `0x04` / `0x05` | Sync start / end | — |
| `0x06` | Settings write | `[autoDim, sleepStartH, sleepStartM, sleepEndH, sleepEndM]` |
| `0x07` | QR key write | `[id, 8-byte token]` |
| `0x08` | Alarm triggered (from clock) | `[id]` |
| `0x09` | Dismiss alarm | `[id, 8-byte token]` |
| `0x0A` | Set timer | duration seconds (uint32) |
| `0x88` | Trigger receipt (ack to clock) | `[id]` |

`dayMask` uses bit 7 (`0x80`) as the enabled flag and bits 0–6 as repeat days (bit 0 = Sun … bit 6 = Sat);
a repeat mask of 0 means a one-time alarm. The clock supports up to **5 alarms**.

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.12`).

```bash
cd smart_ble_alarm
flutter pub get
flutter run           # run on a connected device/emulator
flutter analyze       # static analysis
flutter test          # unit + widget tests
```

On first launch the app opens the pairing screen. To try it **without hardware**, the app can connect to
the built-in simulated clock (device id `simulated_device`).

### Permissions

The app requests Bluetooth scan/connect and location permissions (Android BLE scanning requirement) at
setup, and notification permission for alarms. These can be reviewed under **Settings → Notifications &
Permissions**.

## Project docs

Additional design/spec documents live at the repo root. Where they conflict with the summary above, this
README and the current code are the source of truth:

- [`Smart BLE Alarm Specification.md`](Smart%20BLE%20Alarm%20Specification.md) — full hardware/app spec
- [`UI Design.md`](UI%20Design.md) — UI & navigation spec
- [`Audit 1 report.md`](Audit%201%20report.md) — earlier integration audit
