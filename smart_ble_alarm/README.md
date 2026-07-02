# WakeGuard

Flutter companion app for an autonomous HM-10 BLE alarm clock. The app pairs with the clock, syncs time, alarms, timers, and display settings, and prints QR dismissal codes that must be scanned to silence protected alarms.

## Getting Started

Run from the `smart_ble_alarm` directory:

```sh
flutter pub get
flutter run
```

The real app uses `BleRepositoryImpl`. Tests can inject `SimulatedBleRepositoryImpl` to exercise UI flows without hardware.
