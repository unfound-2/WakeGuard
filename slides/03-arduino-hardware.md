# WakeGuard Clock — Firmware & Hardware

Firmware for the **WakeGuard Clock**, the autonomous bedside alarm node that pairs with the WakeGuard
Flutter app ([`../smart_ble_alarm/`](../smart_ble_alarm/)). Source:
[`WakeGuardClock/WakeGuardClock.ino`](WakeGuardClock/WakeGuardClock.ino).

The clock is the "clock node": the phone is the configuration master and time source, but between
connections the clock runs fully on its own — it keeps time in software (no RTC), stores alarms, settings,
and dismissal tokens in EEPROM, and rings alarms and timers autonomously. It only needs the app to change
configuration or complete a secured (token-gated) dismissal. The BLE protocol below is a **fixed
contract**: do not change the frame format, command IDs, or payload layouts without changing the app to
match ([`ble_framing.dart`](../smart_ble_alarm/lib/data/datasources/ble_framing.dart),
[`ble_payloads.dart`](../smart_ble_alarm/lib/core/ble/ble_payloads.dart)).

## Bill of materials

| Part | Notes |
| --- | --- |
| **Arduino Uno R3** (ATmega328P, 16 MHz) | No RTC — time is kept in software with drift correction. **32 KB flash / 2 KB RAM** budget. |
| **ILI9341 240×320 SPI TFT** (2.4"/2.8") | 3.3 V-logic panel on hardware SPI; touch pins unused. Backlight LED tied straight to 3.3 V (always on). |
| **HM-10 BLE module** | Transparent serial-over-BLE, service `FFE0` / characteristic `FFE1`; advertises as **"WG Clock"**. |
| **Passive piezo / speaker** | Driven by Timer1 PWM on D9 (an active buzzer is also supported — see note). |
| **Momentary push button** *(optional)* | Snooze/dismiss while ringing, on D4. Harmless/ignored if absent. |
| **Photoresistor / LDR** *(optional)* | Ambient auto-dim on A0. Off by default (`ENABLE_LDR 0`). |
| Resistors for level-shifting | ~1 kΩ / 2 kΩ dividers on each 5 V→3.3 V SPI output line (any ~1:2 ratio). |

> The ILI9341 is a 3.3 V-logic panel. Every 5 V Arduino **output** feeding it goes through a ~1:2
> resistor divider (a 5 V HIGH becomes ~3.3 V). MISO is an **input** to the Arduino, so it connects
> directly with no divider. The backlight LED is wired straight to 3.3 V (no GPIO control).

## Wiring table

Pin numbers are taken directly from the `#define`s in `WakeGuardClock.ino`.

| Signal | Arduino pin | Connection | Level-shift |
| --- | --- | --- | --- |
| HM-10 VCC / GND | — | 3.3 V / GND | — |
| HM-10 TXD → Arduino RX | **D2** (`PIN_HM10_TXD`) | HM-10 TXD → D2 | Direct (3.3 V is a valid HIGH at 5 V logic) |
| Arduino TX → HM-10 RXD | **D3** (`PIN_HM10_RXD`) | D3 → HM-10 RXD | **Through 1 k/2 k divider** (5 V → ~3.3 V) |
| Buzzer + | **D9** (`PIN_BUZZER`) | D9 → buzzer → GND | Optional 100 Ω series to tame current |
| Snooze button | **D4** (`PIN_BUTTON`) | D4 → button → GND | Internal pull-up (`INPUT_PULLUP`) |
| LDR (optional) | **A0** (`PIN_LDR`) | A0 divider | Only used if `ENABLE_LDR` |
| TFT VCC / GND | — | 5 V / GND | — |
| TFT **LED** (backlight) | — | **3.3 V (hardwired, always on)** | — |
| TFT SDO / **MISO** | **D12** | Direct (input to Arduino) | Direct, no divider |
| TFT **SCK** (clock) | **D13** | HW-SPI clock | Through divider |
| TFT SDI / **MOSI** | **D11** | HW-SPI data in | Through divider |
| TFT **CS** | **D10** (`TFT_CS`) | Chip select | Through divider |
| TFT **DC/RS** | **D7** (`TFT_DC`) | Data/command | Through divider |
| TFT **RESET** | **D8** (`TFT_RST`) | Reset | Through divider |
| TFT T_* (touch) | — | Left unconnected | — |

Hardware SPI is fixed on the Uno: **MOSI = D11, MISO = D12, SCK = D13**. Only CS/DC/RST are passed to the
`Adafruit_ILI9341` constructor.

## Required libraries

Install via the Arduino IDE Library Manager:

- **Adafruit GFX Library**
- **Adafruit ILI9341**
- **Adafruit BusIO** (a dependency of the above — accept it when prompted)

`SoftwareSerial`, `SPI`, `EEPROM`, and `avr/wdt` ship with the Arduino AVR core.

## Build & flash

1. Open [`WakeGuardClock/WakeGuardClock.ino`](WakeGuardClock/WakeGuardClock.ino) in the Arduino IDE.
2. Install the three libraries above.
3. **Tools → Board → Arduino Uno**; select the serial **Port**.
4. Check the one-time config near the top of the sketch (all `#define`s):
   - `TIMEZONE_OFFSET_SECONDS` — leave at `0`; the app sends local epoch (DST handled phone-side). Only set
     nonzero when pairing with an old app build that still sends UTC.
   - `USE_24H_DISPLAY`, `TFT_ROTATION` (1/3 = landscape 320×240; flip if upside down).
   - `BUZZER_IS_ACTIVE` — defaults to `1` (active buzzer). Set `0` for a passive piezo/speaker to get the
     chime melodies, per-alarm volume, and gradual-wake fade (an active buzzer has fixed pitch/loudness, so
     patterns play as beep rhythms and volume/fade are no-ops).
   - Optional features: `ENABLE_SNOOZE_BUTTON` (D4), `ENABLE_LDR` (A0), `ENABLE_WATCHDOG` (~8 s), `HM10_SET_NAME`.
5. **Upload.** At power-on the clock rename-advertises as "WG Clock", plays a self-test chime (a rising
   0.5→4.5 kHz sweep), shows a splash, then the clock face.

The three sibling sketches `BuzzerTest1_SteadyDC`, `BuzzerTest2_Tone`, and `BuzzerTest3_BitBang` isolate
active-vs-passive-vs-wiring buzzer problems on D9.

## Flash budget & the digit-subset font

The Uno's program space is **32 256 bytes**. The clock face draws large, crisp digits using a custom GFX
font, but the full `FreeSansBold24pt7b` (95 glyphs) costs ~8.8 KB of flash. Since the big time only ever
draws `0-9` and `:`, [`WakeGuardClock/TimeDigits24pt.h`](WakeGuardClock/TimeDigits24pt.h) is a **generated
digits-only subset** (~1 KB) of that font — saving ~7.7 KB, which is what lets the sketch fit while keeping
native-size 24 pt digits. Out-of-range characters (e.g. the ring screen's `a`/`p`) are silently skipped by
`Adafruit_GFX::write()`.

If the sketch ever overflows, step `TIME_FONT_PT` **down**: `24` (crisp digits subset) → `18` → `12` (18/12
use the full Adafruit fonts, drawn smaller/blockier but guaranteed to fit). Setting `USE_CUSTOM_FONTS 0`
falls all the way back to the built-in 5×7 bitmap font. Labels/date/status use `FreeSansBold12pt7b`
(`UI_FONT`, ~4 KB). Regenerate the subset via `scratchpad/gen.py`.

## BLE protocol

### Frame format

```
[ SOF | cmd | len | payload… | checksum | EOF ]
   0x5B '['                                0x5D ']'
```

- **SOF** = `0x5B` (`'['`), **EOF** = `0x5D` (`']'`), **ESC** = `0x5C` (`'\'`).
- **checksum** = `cmd ^ len ^ payload[0] ^ … ^ payload[len-1]` (XOR).
- Every body byte (cmd, len, payload, checksum) equal to SOF/EOF/ESC is prefixed with **ESC** on the wire
  and un-escaped on receipt.
- **`MAX_PAYLOAD` = 15 bytes.** A too-long or bad-checksum frame is rejected with a `0xFF` error.
- The decoder is a non-blocking byte-stream state machine, so frames may split across the HM-10's ~20-byte
  notification chunks.

### App → clock commands

| Opcode | Name (`CMD_*`) | Payload | Meaning |
| --- | --- | --- | --- |
| `0x01` | `TIME_SYNC` | `[epoch uint32 big-endian]` | Set the software clock (local epoch; also refines drift). |
| `0x02` | `ALARM_ADD` | `[id, hour, minute, dayMask, qrRequired, snoozeCount?, snoozeMin?, volume?, fadeSec?]` | Upsert an alarm by id. Bytes past `[4]` are optional (length-guarded); `snoozeCount` (byte 5), snooze length min (6), volume 1–100 (7), gradual-wake fade sec (8). |
| `0x03` | `ALARM_DEL` | `[id]` | Delete the alarm with this id (stops it if ringing). |
| `0x04` | `SYNC_START` | — | Begin a sync batch (defers EEPROM writes). |
| `0x05` | `SYNC_END` | — | End the batch; commit alarm changes to EEPROM in one write. |
| `0x06` | `SETTINGS` | `[flags, theme, accent]` | Clock-face display. flags: bit0 24h, bit1 seconds, bit2 date, bit3 day-of-week, bits4-5 date format. theme 0 dark / 1 light. accent 0–3 (amber/blue/green/violet). |
| `0x07` | `QR_KEY` | `[id, token×8]` | Store the 8-byte dismissal token for a protected alarm. |
| `0x09` | `DISMISS` | `[id, token×8]` | Dismiss request; clock `memcmp`s the token (accepted for unsecured alarms). |
| `0x0A` | `TIMER_SET` | `[seconds uint32 big-endian]` | Start a countdown timer. |
| `0x0B` | `TIMER_STOP` | — | Cancel a running timer / silence a finished-timer chime. |
| `0x0C` | `WEATHER` | `[tempInt8, condCode]` | Push weather (phone has network, clock doesn't). condCode 0–6 = clear/partly/cloudy/rain/snow/thunder/fog; `0xFF` ⇒ hide the corner. |
| `0x0D` | `DISPLAY_SLEEP` | `[enabled, startH, startM, endH, endM]` | Nightly panel-blank window (may wrap past midnight). RAM-only; re-pushed each sync. |
| `0x88` | `RING_ACK` | — | App confirms it received a `0x08` ring; clock stops rebroadcasting. |

### Clock → app responses / notifications

| Opcode | Name | Payload | Meaning |
| --- | --- | --- | --- |
| `0x08` | `NOTIFY_RING` | `[id]` | An alarm started ringing (rebroadcast every ~3 s until `0x88`). |
| `0x81` | `ACK_TIME_SYNC` | — | Time sync applied. |
| `0x82` | `ACK_ALARM_ADD` | `[id]` | Alarm upserted (echoes the id). |
| `0x83` | `ACK_ALARM_DEL` | `[id]` | Alarm deleted (echoes the id). |
| `0x84` | `ACK_SYNC_START` | — | Sync batch started. |
| `0x85` | `ACK_SYNC_END` | — | Sync batch committed. |
| `0x86` | `ACK_SETTINGS` | — | Display settings applied. |
| `0x87` | `ACK_QR_KEY` | — | Dismissal token stored. |
| `0x89` | `ACK_DISMISS` | — | Buzzer silenced / ring stopped (also the successful-dismiss ack). |
| `0x8A` | `ACK_TIMER_SET` | — | Timer started. |
| `0x8B` | `ACK_TIMER_STOP` | — | Timer cancelled / silenced. |
| `0x8C` | `ACK_WEATHER` | — | Weather received. |
| `0x8D` | `ACK_DISPLAY_SLEEP` | — | Sleep schedule received. |
| `0xFF` | `CMD_ERROR` | `[code]` | Error: `0x02` checksum, `0x03` too long, `0x04` invalid command. |

### `dayMask` layout

`bit0 = Sun … bit6 = Sat`, `bit7 = ACTIVE` (arm flag). A repeat mask of 0 (`mask & 0x7F == 0`) is a
one-time alarm, which disarms itself after firing. The clock stores up to **5 alarms** (`MAX_ALARMS`).

A note on `0x09`: a wrong token leaves the buzzer sounding (the wake challenge is enforced). Only a
successful stop emits `0x89`. A secured alarm can be **snoozed** with the physical button but not fully
dismissed by it.

## Firmware internals (quick reference)

- **Timekeeping** — integrates `micros()` into a seconds counter with a measured `driftPPM` correction
  (persisted in EEPROM); rollover-safe.
- **Alarm firing** — matches on `hh:mm` and de-dupes per minute so a time jump or a blocking write can't
  skip an alarm.
- **Sound engine** — Timer1 phase-correct PWM on D9 (OC1A) drives pitch (`ICR1`) and loudness (`OCR1A`),
  with a struck-bell decay envelope and a gradual-wake master fade (passive-buzzer mode).
- **Display** — 320×240 landscape, field-diff rendering (only changed text slots hit the SPI bus),
  full-screen repaint only on a mode change; rendering pauses during a sync so it can't starve the BLE RX.
- **Reliability** — EEPROM persistence with a version guard, ~5-min display self-heal re-init, ~8 s
  hardware watchdog, and a boot self-test chime.
- **Loop order** — `pumpBle → tickClock → checkAlarms → serviceRing → serviceTimer → serviceBuzzer →
  serviceButton → serviceSyncFlush → renderTft`, all non-blocking.
</content>
