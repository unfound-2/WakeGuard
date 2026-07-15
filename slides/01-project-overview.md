# WakeGuard — Smart BLE Alarm Clock

WakeGuard is a companion mobile app for an **autonomous Bluetooth alarm clock** built to help people
with narcolepsy (and other conditions that make waking difficult) actually get out of bed. Unlike a
normal alarm that a single tap can silence, a WakeGuard alarm keeps sounding until the user physically
completes a **wake challenge** — reducing the chance of falling straight back asleep.

The product has two halves, both in this repo:

| Component | Role | Location |
| --- | --- | --- |
| **Mobile app** (Flutter) | Configure alarms/timers, sync the clock over BLE, run the wake challenge to dismiss | [`smart_ble_alarm/`](smart_ble_alarm/) |
| **Clock firmware** (Arduino + HM-10 BLE) | Keeps time standalone, stores alarms/tokens, drives an ILI9341 TFT + buzzer | [`arduino/WakeGuardClock/`](arduino/WakeGuardClock/) |

Once the clock has been synced, it runs **independently of the phone**: it keeps time in software (no RTC),
stores alarms and dismissal tokens in EEPROM, and fires alarms and timers on its own even with no phone
connected. The phone is only needed to change configuration, push time/weather, and run the wake challenge
that dismisses a ringing alarm.

## Architecture

```
┌────────────────────────┐        framed BLE serial        ┌──────────────────────────┐
│   Flutter app          │   (HM-10, service FFE0 /        │   Arduino Uno R3          │
│   (smart_ble_alarm)    │    characteristic FFE1)         │   (WakeGuardClock)        │
│                        │  ───────────────────────────▶   │                           │
│  • alarm/timer config  │    0x01 time, 0x02 alarms,      │  • software clock + drift │
│  • time + weather push │    0x06 display, 0x0C weather,  │  • EEPROM alarm store     │
│  • wake-challenge UI    │    0x0D sleep, 0x09 dismiss…    │  • ILI9341 TFT clock face │
│                        │  ◀───────────────────────────   │  • Timer1-PWM buzzer      │
│  • BLE + backup notifs │    0x08 ring, 0x89 dismiss-ack, │  • autonomous ring/snooze │
└────────────────────────┘    0x8x ACKs, 0xFF error        └──────────────────────────┘
```

The phone is the configuration master and authoritative time source; the clock is an autonomous
"clock node". They speak a **fixed, framed byte protocol** matched byte-for-byte on both sides
([`ble_framing.dart`](smart_ble_alarm/lib/data/datasources/ble_framing.dart) ⇄
[`WakeGuardClock.ino`](arduino/WakeGuardClock/WakeGuardClock.ino)).

The Flutter app follows a clean-architecture / feature-first layout under
[`smart_ble_alarm/lib/`](smart_ble_alarm/lib/), with `flutter_bloc` for state management and a
"Liquid Glass" design system (light + dark). A **simulated BLE repository**
(`SimulatedBleRepositoryImpl`, device id `simulated_device`) lets the app run end-to-end with no
hardware — enter "developer mode" from the pairing screen (debug builds) to explore the connected UI,
sync, and dismissal without a physical clock.

## Repo layout

```
Alarm-Clock/
├── smart_ble_alarm/          # Flutter companion app
│   ├── lib/
│   │   ├── app/              # bootstrap, navigation, root widget
│   │   ├── core/             # ble payloads/sync, theme (Liquid Glass), audio,
│   │   │                     #   notifications, firebase, utils
│   │   ├── data/             # BLE framing, secure token storage, image
│   │   │                     #   recognition, weather; real + simulated repos
│   │   ├── domain/           # Alarm entity, BleRepository interface, use cases
│   │   └── features/         # alarms, bluetooth/clock, dedicated_clock,
│   │                         #   wake_challenge, timers, display, settings,
│   │                         #   home, account, history, onboarding
│   └── pubspec.yaml
├── arduino/
│   ├── WakeGuardClock/       # clock firmware (.ino + TimeDigits24pt.h font)
│   └── BuzzerTest1/2/3/      # standalone buzzer diagnostics (DC / tone / bit-bang)
├── app store metadata/       # store assets (e.g. routing-coverage geojson)
├── agent reference/          # spec, UI design, audits, privacy policy, CLAUDE.md
└── docs/FEATURES.md          # full app + clock feature list
```

## How dismissal works

When an alarm fires the buzzer sounds until the wake challenge is completed. Each alarm chooses one of
three dismissal modes (see [`ringing_dismissal.dart`](smart_ble_alarm/lib/features/alarms/presentation/widgets/ringing_dismissal.dart)):

- **No challenge** (`!qrRequired`) — a plain **Dismiss** button silences the clock (sends `0x09` with a
  zero token, which the clock accepts for unsecured alarms).
- **Object photo / item scan** (`usesItemScan`) — **Take Photo** of a real-world object chosen when the
  alarm was created (e.g. a toothbrush). The app recognises it **on-device** with Google ML Kit image
  labeling (no network); a saved text description reminds the user what to find.
- **QR backup code** (`qrRequired`, no item) — **Scan QR** of the printed backup code.

The **backup code** is a single, app-wide printed QR that works for **every** protected alarm. It is an
8-byte HMAC-SHA256 token held in secure storage; it is intentionally **static** so a printed paper code
stays valid indefinitely. Because the code lives on paper away from the bed, scanning it forces the user
up. You print it once from the **Clock tab → Backup Code**. For item alarms, the printed code is a gated
fallback that unlocks only **3 minutes** after the alarm starts ringing — there is deliberately no free
"dismiss anyway".

The ringing dismissal action appears on **three surfaces** so it's always reachable: a global banner over
every tab, the big Home ring card, and the Alarms-tab card (which turns red and shows a "Ringing now" pill).

## BLE protocol

The phone talks to the HM-10 module (service `FFE0`, characteristic `FFE1`, single RX/TX characteristic)
using a framed byte protocol ([`ble_framing.dart`](smart_ble_alarm/lib/data/datasources/ble_framing.dart)):

```
[ SOF(0x5B '[') | cmd | len | payload… (escaped) | checksum (XOR) | EOF(0x5D ']') ]
```

Checksum is `cmd ^ len ^ payload…`. Every body byte (cmd, len, payload, checksum) that equals
`SOF`/`EOF`/`ESC`(`0x5C`) is escaped with `ESC`; frames are sent in ≤20-byte MTU chunks. **Max payload =
15 bytes.** App → clock commands:

| Cmd | Meaning | Payload |
| --- | --- | --- |
| `0x01` | Time sync | local-epoch seconds (uint32 BE; UTC secs + tz offset, so the phone owns DST) |
| `0x02` | Add/update alarm (upsert) | `[id, hour, minute, dayMask, qrRequired, snoozeCount, snoozeDuration, volume, gradualWake]` (up to 9 bytes) |
| `0x03` | Delete alarm | `[id]` |
| `0x04` / `0x05` | Sync start / end | — (brackets a sync batch) |
| `0x06` | Clock display settings | `[flags, theme, accent]` (flags: bit0 24h, bit1 seconds, bit2 date, bit3 day-of-week, bits4-5 date format) |
| `0x07` | Store dismissal token | `[id, 8-byte token]` (pushed to each protected slot) |
| `0x09` | Dismiss alarm | `[id, 8-byte token]` (clock `memcmp`s vs stored token; zero token OK if unsecured) |
| `0x0A` / `0x0B` | Timer set / stop | duration seconds (uint32 BE) / — |
| `0x0C` | Weather push | `[tempInt8, conditionCode]` (`0xFF` condition ⇒ hide the corner) |
| `0x0D` | Display-sleep schedule | `[enabled, startH, startM, endH, endM]` (nightly panel blank, may wrap midnight) |
| `0x88` | Ring receipt (app → clock) | app confirms it saw `0x08`, stopping rebroadcast |

Clock → app frames: `0x08` alarm-triggered `[id]` (rebroadcast until `0x88`); `0x89` dismiss ack (ring
stopped); `0x81`–`0x87`, `0x8A`–`0x8D` are ACKs echoing the matching command; `0xFF` error `[code]`
(`0x02` checksum, `0x03` too long, `0x04` invalid command).

`dayMask` uses bit 7 (`0x80`) as the enabled flag and bits 0–6 as repeat days (bit 0 = Sun … bit 6 = Sat);
a repeat mask of 0 means a one-time alarm. The clock supports up to **5 alarms**. The `0x02` frame is a
length-guarded positional frame: the firmware reads each trailing byte only under a `len >=` guard, so it
stays backward-compatible — but its layout must only ever be extended by a **coordinated app + firmware
change** (both sides plus the `Alarm.syncHash` fold). See [`arduino/README.md`](arduino/README.md) for the
full opcode/ACK tables and hardware wiring.

## Getting started

### Build the app

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.12`).

```bash
cd smart_ble_alarm
flutter pub get
flutter run           # run on a connected device/emulator
flutter analyze       # static analysis (keep clean)
flutter test          # unit + widget tests
flutter build ipa     # iOS / TestFlight build
```

The app ships a `WakeGuard` product flavor (default). On first launch it shows onboarding, then the
pairing screen. You can **Skip** pairing (persisted; the app runs offline with alarms saved locally +
mirrored to backup notifications, re-pairing under **Settings → Connect a Clock**), or enter the built-in
simulated clock in debug builds.

**Platform support:** iOS and Android (Flutter). BLE is **foreground-only, on-demand** — the Arduino is
autonomous, so the app connects to configure/sync and does not hold a background BLE session. On iOS the
app can also act as a **Dedicated Clock** (a spare phone becomes a bedside clock face) or a **Phone Alarm
companion** (a foreground backup ringer) — see [`docs/FEATURES.md`](docs/FEATURES.md).

### Flash the firmware

The firmware lives in [`arduino/WakeGuardClock/`](arduino/WakeGuardClock/) — open `WakeGuardClock.ino` in
the Arduino IDE, install the **Adafruit GFX**, **Adafruit ILI9341**, and **Adafruit BusIO** libraries,
select **Board = Arduino Uno** and the serial port, and Upload. The buzzer is on **pin D9**; three
standalone `arduino/BuzzerTest*` sketches isolate active-vs-passive-vs-wiring buzzer issues. Full bill of
materials, wiring table, the 32 KB-flash font note, and the protocol tables are in
[`arduino/README.md`](arduino/README.md).

### Permissions

The app requests Bluetooth scan/connect and location permissions (Android BLE-scanning requirement, iOS
purpose strings), camera permission for the QR and object scans, and notification permission for backup
alarms.

## Project docs

- [`docs/FEATURES.md`](docs/FEATURES.md) — full app + clock feature list
- [`arduino/README.md`](arduino/README.md) — firmware/hardware guide (BOM, wiring, build, BLE protocol)
- [`agent reference/CLAUDE.md`](agent%20reference/CLAUDE.md) — engineering brief (architecture, protocol, conventions)
- [`PROJECT_LOG.md`](PROJECT_LOG.md) — attribution + full log of features and implementations
- [`agent reference/Smart BLE Alarm Specification.md`](agent%20reference/Smart%20BLE%20Alarm%20Specification.md) — full hardware/app spec
- [`agent reference/UI Design.md`](agent%20reference/UI%20Design.md) — UI & navigation spec

Where these conflict, the current code, this README, and `arduino/README.md` are the source of truth.
</content>
</invoke>
