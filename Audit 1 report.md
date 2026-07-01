# Project Audit Report 1

## Executive Summary
An end-to-end audit of the Smart BLE Alarm project was conducted. The UI layer, state management, and Bluetooth abstraction have been well-architected. However, several critical integration gaps were found between the UI logic and the hardware communication protocol. Additionally, some data persistence requirements and UI placeholders remain unresolved.

## Issues Identified

### 1. Bluetooth Time Sync Protocol Mismatch
* **Severity**: **Critical**
* **Why it matters**: `main_screen.dart` currently sends a 3-byte payload `[hour, minute, second]` when executing the `0x01 TIME_SYNC_WRITE` command. The hardware specification explicitly requires a 4-byte `[Epoch Time: uint32]`. The Arduino node will fail to parse this packet, leading to complete failure of the standalone clock schedule.
* **Recommended Fix**: Update the background sync logic to calculate the current Unix Epoch (in seconds) and encode it as a 4-byte array before transmission.
* **Files affected**: `lib/presentation/screens/main_screen.dart`
* **Action**: Fix immediately.

### 2. Missing Local Data Persistence for Alarms
* **Severity**: **Critical**
* **Why it matters**: `AlarmBloc` currently holds alarm schedules entirely in memory (`// In a full implementation, this would load from local database`). The specification mandates offline capability where edits are stored locally. If the app is closed, all alarms are lost from the phone's UI.
* **Recommended Fix**: Integrate `SharedPreferences` encoding into `AlarmBloc` to write/read the `List<Alarm>` to disk on every `AddOrUpdateAlarmEvent` and `DeleteAlarmEvent`.
* **Files affected**: `lib/presentation/blocs/alarm_bloc/alarm_bloc.dart`
* **Action**: Fix immediately.

### 3. QR Code Dismissal Incomplete
* **Severity**: **Critical**
* **Why it matters**: The `ScannerScreen` successfully verifies the QR code signature, but it includes a placeholder comment: `// Send ALARM_DISMISS packet in real app`. It does not actually dispatch the `0x09 ALARM_DISMISS` command to the hardware. The physical clock will continue ringing.
* **Recommended Fix**: Update `ScannerScreen` to access the `BleConnectionBloc` and dispatch the `0x09` packet with the payload `[AlarmID] [8-byte token]`.
* **Files affected**: `lib/presentation/screens/scanner_screen.dart`
* **Action**: Fix immediately.

### 4. "Start Timer" Quick Action Placeholder
* **Severity**: **High**
* **Why it matters**: In `home_tab.dart`, the "Start Timer" action button has an empty `onTap: () {}` callback. The requirements explicitly state there must be no placeholder features.
* **Recommended Fix**: Implement a dialog that allows the user to pick a duration, then dispatch the `0x0A TIMER_SET` command `[DurationSeconds: uint32]` to the connected clock.
* **Files affected**: `lib/presentation/screens/tabs/home_tab.dart`
* **Action**: Fix immediately.

### 5. Settings "Developer" Placeholders
* **Severity**: **High**
* **Why it matters**: The "Developer (Hidden)" section in `settings_screen.dart` contains non-functional list items ("BLE Logs", "Debug Information", "Firmware Version").
* **Recommended Fix**: Remove this section entirely to eliminate placeholders and prevent scope creep, as these features are not required for core functionality.
* **Files affected**: `lib/presentation/screens/settings_screen.dart`
* **Action**: Fix immediately.

### 6. Settings Sync Protocol Mismatch (Sleep Schedule)
* **Severity**: **Medium**
* **Why it matters**: The app sends a 5-byte payload for `0x06 SETTINGS_WRITE`: `[AutoDim, StartHour, StartMinute, EndHour, EndMinute]`. The specification document defined it as 3 bytes: `[AutoDim] [SleepStart] [SleepEnd]`. The 5-byte structure provides better UX (minute-precision schedules).
* **Recommended Fix**: Retain the 5-byte payload in the app architecture. Standardize this format for future firmware development rather than downgrading the app's capability.
* **Files affected**: N/A (Documentation/Architecture note)
* **Action**: No code changes required.

### 7. QR Code Payload Specification Discrepancy
* **Severity**: **Low**
* **Why it matters**: The specification states that the QR token rotates daily using an `EpochDayStamp`. However, since the QR code is printed via AirPrint on physical paper, rotating the token daily would require users to print a new code every 24 hours. The codebase currently uses a static payload `[AlarmId]`, which is much more practical for physical media.
* **Recommended Fix**: Keep the static implementation in `secure_key_datasource.dart`. Note the architectural deviation from the spec.
* **Files affected**: `lib/data/datasources/secure_key_datasource.dart`
* **Action**: No code changes required.
