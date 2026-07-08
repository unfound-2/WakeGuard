# WakeGuard

Flutter companion app for the WakeGuard Bluetooth alarm clock. The app pairs with the clock over BLE
(HM-10 UART), syncs time, alarms, timers, and display settings, and requires a **wake challenge** before
a protected alarm can be dismissed. The clock is autonomous — it keeps time and rings on its own; the app
configures it and runs the challenge.

Two wake-challenge methods per alarm:

- **Object photo** — the user picks a morning-routine object away from bed, then photographs it when the
  alarm rings. Recognition runs **on-device** via Google ML Kit image labeling (no network).
- **QR backup code** — a single, app-wide printed code (static 8-byte HMAC-SHA256 token) that dismisses
  any protected alarm. Printed once from **Clock tab → Backup Code**; for object alarms it's a gated
  fallback that unlocks 3 minutes after the ring starts.

An alarm can also require no challenge (plain Dismiss).

See the repo-root [`README.md`](../README.md) for the full product overview and BLE protocol, and
[`CLAUDE.md`](../CLAUDE.md) for the engineering brief.

## Getting Started

Run from the `smart_ble_alarm` directory:

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

The real app uses `BleRepositoryImpl`. Debug builds can enter "developer mode" from the pairing screen to
inject `SimulatedBleRepositoryImpl` and exercise the connected UI (sync, ringing, dismissal) without
hardware.
