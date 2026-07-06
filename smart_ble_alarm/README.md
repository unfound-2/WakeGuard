# WakeGuard

Flutter companion app for a WakeGuard Bluetooth alarm clock. The app pairs with the clock, syncs time, alarms, timers, and display settings, and requires a wake challenge before protected alarms can be dismissed.

The product target is AI-powered object verification: users choose a morning-routine object away from bed, then verify that object from the app when the alarm rings. This build includes the object-selection UX and secure backup-code dismissal path; the production AI verifier still needs to be connected before QR fallback can be removed.

## Getting Started

Run from the `smart_ble_alarm` directory:

```sh
flutter pub get
flutter run
```

The real app uses `BleRepositoryImpl`. Tests can inject `SimulatedBleRepositoryImpl` to exercise UI flows without hardware.
