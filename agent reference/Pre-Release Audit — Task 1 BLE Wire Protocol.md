# Pre-Release Audit — Task 1: BLE Wire Protocol Integrity

> Audit of §14 #1 / §9 Order 1 of `Production Pre-Release Audit Spec.md`.
> **Scope:** confirm the Flutter app and the clock firmware agree **byte-for-byte** on
> framing, checksum, the 9-byte `0x02` layout, and the length-guarded extension rule.
> **Method:** static cross-read of the two codebases at `main`. Files compared:
> `ble_framing.dart`, `ble_payloads.dart`, `alarm.dart`, `ble_repository_impl.dart`,
> `main_screen.dart`, `secure_key_datasource.dart`, and `WakeGuardClock.ino`.
> **Verdict:** ✅ **PASS (static).** App and firmware agree on every wire element checked.
> Runtime radio behavior (chunking/mutex on real HM-10) is a separate manual target (§10 #2).

---

## 1. Framing — AGREE

| Element | App (`ble_framing.dart`) | Firmware (`WakeGuardClock.ino`) | Match |
|---|---|---|---|
| SOF | `0x5B` (:2) | `0x5B` (:223) | ✅ |
| EOF | `0x5D` (:3) | `0x5D` (:224) | ✅ |
| ESC | `0x5C` (:4) | `0x5C` (:225) | ✅ |
| Body order | `[cmd, len, data…, cs]` (:23) | `[cmd, len, data…, cs]` (:690–701) | ✅ |
| Checksum | `cs = cmd ^ len ^ data…` (:13–16) | `cs = cmd ^ len ^ data…` (:685–686) | ✅ |
| Escaping | uniform: every body byte == SOF/EOF/ESC (:23–28) | uniform: cmd, len, each data byte, cs (:691–700) | ✅ |
| Max payload | 15, throws on encode (:8–10); decode rejects `len>15` (:117) | `MAX_PAYLOAD=15` (:226); send drops (:684); recv `ERR_TOO_LONG` (:741) | ✅ |
| Unescape start | from byte after SOF, uniform (:56–82) | from first body byte, uniform (:727–735) | ✅ |
| Stray SOF | restart frame (:70–74) | restart, `rxLen=0` (:735) | ✅ |
| Exact-length check | `frame.length == 3 + len` (:117) | `rxLen == len + 3` (:743) | ✅ |
| Partial / dropped-EOF recovery | keep partial; drop SOF if buffer > ~40 B (:85–97) | `rxBody[MAX_PAYLOAD+3]=18`; overrun → `resetRx()` (:729/757) | ✅ (equivalent) |

**Max-frame buffer sizing (checked for off-by-one).** Firmware `rxBody` holds **unescaped** body
bytes (ESC is consumed before store, :728–734). A maximal frame is `cmd + len + 15 data + cs = 18`
bytes → `sizeof(rxBody) == 18`, and `len(15)+3 == 18`. Exact fit; no truncation of a legal max
frame. ✅

---

## 2. Checksum validation on receive — AGREE

- App recomputes `cmd ^ len ^ data…` and compares to `frame[2+len]`; a mismatch **silently drops**
  the frame (`_isValidUnescapedFrame`, :112–128). The app is receive-only for errors — it never
  emits `0xFF`.
- Firmware recomputes and compares to `rxBody[2+len]`; mismatch → `sendError(ERR_CHECKSUM=0x02)`,
  over-length → `ERR_TOO_LONG=0x03`, unknown cmd → `ERR_INVALID_CMD` (:744–751, :897).

Checksum algorithm and placement are identical in both directions. ✅

---

## 3. `0x02` ALARM_ADD 9-byte layout — AGREE (exact positional match)

| Byte | App `BlePayloads.alarm` (`ble_payloads.dart:49–59`) | Firmware `CMD_ALARM_ADD` (`:781–795`) | Guard |
|---|---|---|---|
| 0 | `id` | `data[0]` id | `len>=5` |
| 1 | `hour` | `data[1]` hour | `len>=5` |
| 2 | `minute` | `data[2]` minute | `len>=5` |
| 3 | `dayMask` | `data[3]` dayMask | `len>=5` |
| 4 | `qrRequired?1:0` | `data[4]` qrRequired | `len>=5` |
| 5 | `wireSnoozeCount` | `data[5]` snoozeCount, else `SNOOZE_MAX_COUNT` | `len>=6` |
| 6 | `wireSnoozeDuration` | `data[6]` snoozeMinutes, else 0 | `len>=7` |
| 7 | `wireVolume` (1–100) | `data[7]` volume, else 0→`VOLUME_DEFAULT` | `len>=8` |
| 8 | `wireGradualWake` | `data[8]` fadeSeconds, else 0 | `len>=9` |

- **`dayMask` bit semantics agree:** app `0x80` = enabled / bits 0–6 = Sun..Sat (`alarm.dart:66,129`);
  firmware `ACTIVE_BIT=0x80`, `DAY_BITS_MASK=0x7F` (`:271–272`), day match `1 << t.dow` (:1001).
- **One-time auto-disable agrees:** app clears `0x80` on ring-clear; firmware disarms when
  `(dayMask & 0x7F)==0` at `startRing` (:924–927) — explicitly cross-referenced in the firmware comment.
- **`volume` mapping:** app sends 1–100; firmware maps `vol*255/100` (:918). `0` = "use default" on
  both sides. ✅

**Length-guarded extension rule — CORRECTLY IMPLEMENTED.** The frame's declared `len` is the true
payload length (app always sends 9). Firmware validates the full frame (`rxLen==len+3`, checksum over
all `len` bytes) and then reads bytes `[5..8]` **only** under matching `len>=` guards, ignoring any
byte beyond `[8]` (:783–785). An older 5-field firmware receiving a 9-byte frame reads the first five
and drops the rest safely; a newer field would require the app to send `len>=10`. The app+firmware
`0x02` extension contract is sound. ✅

`Alarm.syncHash` (`alarm.dart:110–127`) folds exactly the 8 wire-relevant bytes (hour, minute,
dayMask, qrRequired, snooze count/duration, volume, gradualWake) via FNV-1a — same bytes the firmware
consumes, so the "needs re-sync?" signal cannot disagree with what is actually on the wire. ✅

---

## 4. All other commands — AGREE

| Cmd | App send site | Firmware handler | Match |
|---|---|---|---|
| `0x01` TIME_SYNC (uint32 BE) | `uint32()` big-endian (`ble_payloads.dart:6–14`) | `data[0]<<24…` (`:772–778`) | ✅ (both treat as **local** epoch — see §5.1) |
| `0x03` ALARM_DEL `[id]` | `id & 0xFF` (`alarm_bloc.dart`) | `len>=1`, `data[0]` (:801) | ✅ |
| `0x04/0x05` SYNC bracket | — | `:806–818` (EEPROM flush at END) | ✅ |
| `0x06` SETTINGS `[flags,theme,accent]` | `clockDisplaySettings` bit0=24h…bits4-5=fmt (`:71–86`) | `data[0]&0x01…(>>4)&0x03`, theme≤1, accent≤3 (:819–839) | ✅ bit-exact |
| `0x07` QR_KEY `[id, token×8]` (9 B) | `[id&0xFF, …token(8)]` (`alarm_bloc.dart:530`) | `len>=9`, `storeToken(data[0], &data[1])` (:841) | ✅ |
| `0x09` DISMISS `[id, token×8]` (9 B) | zero token (`ringing_dismissal.dart:84`) / real token (`scanner_screen:65`, `item_scan:127`) | `len>=9`, `memcmp(...,8)` (:846, :954) | ✅ |
| `0x0A` TIMER_SET (uint32 BE) | `uint32(seconds)` (`create_timer_sheet.dart:73`) | `data[0]<<24…` (:852) | ✅ |
| `0x0B` TIMER_STOP (no payload) | `alarms_tab.dart:639` | `stopTimer()`, payload ignored (:861) | ✅ |
| `0x0C` WEATHER `[temp int8, cond]` | `[temp&0xFF, cond&0x07]` / hidden `[0,0xFF]` (`:96–105`) | `int8` temp, `0xFF`→hide, else ≤6 (:866) | ✅ |
| `0x0D` DISPLAY_SLEEP `[en,sH,sM,eH,eM]` | `clockSleepSchedule` (`:115–129`) | `len>=5`, validates <24/<60 (:880) | ✅ |
| `0x08` NOTIFY_RING `[alarmId]` (clock→app) | reads `data.first` (`main_screen.dart:137`) | `sendFrame(NOTIFY_RING,&id,1)` (:1024) | ✅ |
| `0x88` RING_ACK `[alarmId]` (app→clock) | `main_screen.dart:141` | sets `appAckedRing`, payload ignored (:894) | ✅ |
| `0x89` ACK_DISMISS (clock→app) | `command == 0x89` (`main_screen.dart:143`) | `endRing`→`sendAck(0x89)` (:939) | ✅ |
| ACK echoes `0x81–0x87/0x8A–0x8D` | (ignored, fire-and-forget) | `ACK_*` constants match app doc 1:1 (:244–256) | ✅ |

Inbound decode path confirmed: `ble_repository_impl.dart:116–119` feeds bytes to
`BleFraming.decodeFrames` and re-emits `[cmd, len, data…]`, which `main_screen.dart:133–135` reads as
`frame[0]=cmd, frame[1]=len, data=skip(2).take(len)`. ✅

---

## 5. Observations recorded (leads — not fixed, per spec)

Ordered by protocol-integrity relevance. Items marked **[§13]** confirm an existing spec target; **[NEW]** was not in §13.

1. **[§13 + NEW consequence] XOR-only checksum + app discards `0xFF` = undetected silent corruption.**
   The frame checksum is a single XOR byte (no CRC) — it misses two-bit errors in the same column and
   byte transpositions. Because the app and firmware use the *same* XOR, a corrupted frame that passes
   on-air passes on **both** sides and writes wrong alarm/setting bytes. Compounding it: the app's
   inbound handler (`main_screen.dart:137–145`) only acts on `0x08`/`0x89` and **ignores `0xFF`
   CMD_ERROR and every ACK**, and `sendCommand` is fire-and-forget (no ACK awaited). So when the clock
   *does* reject a frame (`ERR_CHECKSUM`/`ERR_TOO_LONG`/`ERR_INVALID_CMD`, firmware :742/750/897) the
   app never learns the alarm didn't land. Partly mitigated by write-with-response chunk delivery
   (`ble_repository_impl.dart:159–171`), which guards *chunk* loss but not frame-level rejection.
   This is the single "byte error silently breaks the clock" surface the spec flags. §13 records the
   XOR-only integrity; the app-ignores-`0xFF` half is **new**.

2. **[§13] `id` handling asymmetry — throw vs mask.** `0x02` build throws `ArgumentError` for `id>255`
   (`ble_payloads.dart:28–35`) while `0x03/0x07/0x09/0x88` mask `id & 0xFF`. Not live: `_nextAlarmId`
   scans 1..255 and the firmware `id` is `uint8_t`, so ids never exceed 255 in practice. Consistent
   with firmware; recorded only as latent inconsistency.

3. **[NEW] Extension rule is one-directional in practice.** The length-guarded `0x02` contract is
   implemented correctly, but is only ever exercised at `len==9` (the app has no path that sends fewer
   or more). The firmware's `len>=5` acceptance of shorter legacy frames and its "ignore bytes beyond
   `[8]`" headroom are untested by the current app. Adding a 10th field would require a coordinated
   app send-side change — matching the "do not change one side alone" rule in CLAUDE.md §11.

4. **[Confirms §13] `0x01`/`0x0A` transmit phone LOCAL wall-clock as the epoch** (`ble_payloads.dart:16–26`).
   App and firmware **agree** on this convention (firmware `TIMEZONE_OFFSET_SECONDS=0`), so it is not a
   protocol mismatch — but DST/timezone correctness is a runtime manual target (§10 #8), not verifiable here.

5. **[Minor] Weather condCode width.** App masks `cond & 0x07` (0..7) but only 0..6 are defined; a stray
   `7` would be sent and the firmware clamps `>6` to `2` (cloudy, :872). Harmless; `WeatherDatasource`
   is expected to emit only 0..6.

6. **[Observation] `0x09` with `len<9` yields neither dismiss nor ACK** (firmware only ACKs via
   `endRing` on success, :846–850). Not live — the app always sends 9 bytes — but a malformed short
   dismiss would leave the clock ringing with no error frame.

---

## 6. Conclusion

The app ↔ firmware **byte contract is consistent** on framing, checksum, the 9-byte `0x02` layout, and
the length-guarded extension rule — the four things §14 #1 requires. Task 1 **passes** at the static
level. The load-bearing residual risk is not a disagreement but the **XOR-only integrity check combined
with the app ignoring `0xFF` error frames** (Observation 1): a mangled-but-checksum-valid frame corrupts
clock state undetected. Recorded for the audit's findings backlog; no fix applied per the spec's
record-only rule.

**Still requires hardware / runtime (out of static scope, per §10 #1–#3):** end-to-end HM-10 framing over
a real radio, 20-byte chunk reassembly under the write mutex, and the `0x09` token `memcmp` round-trip on
the reference clock running a build that reads the full 9-byte `0x02` frame (open question §12 #1).
