# WakeGuard — Project Log & Contributions

## Attribution

**WakeGuard is the work of Aaron Hua.** Every design decision, product-direction call, feature idea, UX
choice, and all hardware and app testing were conceived, directed, and validated by Aaron. An AI assistant
(Claude, via Claude Code) was used as a **coding and auditing tool** — it generated, refactored, reviewed,
and documented code under Aaron's direction, and surfaced issues for Aaron to decide on. It did not
originate the product vision or make the product decisions; it implemented and audited against Aaron's
specifications and judgment.

In short:
- **Aaron Hua** — creator: product vision, all feature ideas, all design/UX decisions, the hardware build
  and wiring, and all real-world testing (BLE, alarms, buzzer, TestFlight).
- **AI assistant** — generated and audited code, implemented Aaron's decisions, wrote tests and docs,
  and flagged trade-offs for Aaron to choose.

### Collaborator credit — Mekyle Alam

Mekyle Alam (GitHub `unfound-2`) built the **onboarding software** (the onboarding flow / screens and
pairing-progress UI, merged into `main` via the `onboarding` branch), and contributed **feature and idea
generation** plus some **UI** work — helping brainstorm features and directions for the app, including
around the **wake-challenge / on-device image-scanning** experience. This was a modest slice of the
project: the bulk of the app — its architecture, BLE protocol, the wake-challenge and single-backup-code
systems, alarms/timers/clock control, sync, and the Liquid Glass design system — was designed by Aaron and
implemented under his direction. The onboarding and wake-challenge features have since been substantially
reworked.

---

## Aaron's contributions (design & direction)

- **Product concept**: an autonomous alarm clock for people with narcolepsy that can't be silenced with a
  tap — dismissal requires a physical wake challenge so the user actually gets up.
- **System split**: a self-sufficient Arduino + HM-10 clock that keeps time and rings on its own, plus a
  Flutter companion app that configures it — the phone is never a dependency for the alarm firing.
- **Wake-challenge design**: on-device object-photo verification as the primary experience, with a printed
  QR backup code; the decision to gate the item-alarm backup to 3 minutes and to have **no** free
  "dismiss anyway".
- **The "one global backup code" decision**: one printed code should dismiss any alarm (accepting the
  documented trade-off that a leaked code works everywhere) — and that the single Print button belongs in
  the Clock tab, removed from alarm cards and the editor.
- **UX decisions**: the Liquid Glass visual direction; four-tab navigation (Home/Alarms/Clock/Settings);
  Settings = universal prefs only, wake challenge is per-alarm; banners must overlay content, not push it;
  ringing state must be unmistakable on the Alarms card; snackbars must not queue.
- **Hardware**: the physical build, wiring (buzzer on D9 → GND), and the hands-on buzzer diagnosis
  (cleaned contacts, reflashed, confirmed wiring) that isolated a hardware-vs-firmware question.
- **Release direction**: first beta as `0.1.0`, rebrand to the `com.aaronhua.wakeguard` identity, and the
  TestFlight submission (including handling the ITMS-90683 rejection and export-compliance answer).
- **Testing & validation**: all on-device and hardware testing, and the acceptance of each trade-off.

---

## Everything in the app right now (feature & implementation log)

This is the cumulative state — a complete, two-halves product (a Flutter app **and** custom Arduino
firmware speaking a hand-rolled binary BLE protocol), spanning UI, state management, cryptography,
on-device ML, embedded C++, and an App Store release. Grouped by area, with the specifics.

### A custom binary BLE protocol (app ↔ firmware, byte-for-byte)
- Designed and implemented a **framed serial-over-BLE protocol** end to end — the exact same wire format
  written twice, once in Dart (`ble_framing.dart`) and once in Arduino C++ (`sendFrame`/decoder), and
  proven to agree byte-for-byte.
- **Frame format**: `SOF(0x5B '[') · cmd · len · payload… · XOR-checksum · EOF(0x5D ']')`, with a uniform
  **escape scheme** — any body byte equal to SOF/EOF/ESC(`0x5C`) is escaped so a data byte can never be
  mistaken for a delimiter. The decoder reassembles frames from a rolling buffer.
- **20-byte MTU chunking** to fit the HM-10's BLE 4.0 packet limit, with a **mutex** serializing concurrent
  writes over the single RX/TX characteristic so two callers can't interleave bytes on the wire.
- A **14-command instruction set**: time sync, alarm upsert/delete, sync-batch brackets, clock settings,
  token store, dismiss, timer set/stop — plus a clock→app **ring handshake** (`0x08` rebroadcast until the
  app acks with `0x88`), a dismiss ack (`0x89`), per-command ACK echoes (`0x81`–`0x8B`), and an error
  channel (`0xFF`).
- **Forward/backward-compatible frame evolution**: the `0x02` alarm frame grew from 5 → 9 bytes (adding
  snooze count, snooze length, volume, and gradual-wake fade) as a **length-guarded positional frame** —
  the firmware reads each trailing byte only under a `len >=` guard, so a newer app and older firmware (or
  vice-versa) still interoperate and simply fall back to defaults. Extending it is a deliberate, coordinated
  app+firmware change.

### Autonomous clock firmware (Arduino + HM-10)
- **Software timekeeping engine with drift calibration** — the Arduino has no RTC, so the firmware keeps
  time in software and compensates for ceramic-resonator drift, staying accurate across long offline
  stretches.
- **EEPROM persistence** of alarms, settings, and dismissal tokens (with a magic-byte layout) so the clock
  survives power loss and keeps ringing on schedule with no phone present.
- **Secured dismissal on-device**: each protected alarm slot stores an 8-byte token; a dismiss request is
  accepted only on a constant-`memcmp` match (unsecured alarms accept a zero token). The buzzer keeps
  sounding on a wrong token — the wake challenge is enforced in hardware, not just the app.
- **Buzzer diagnostics**: three standalone sketches (steady-DC, `tone()` 2 kHz, bit-bang ~1 kHz) that
  isolate an active-vs-passive-buzzer / wiring fault as a clean code-vs-hardware discriminator.

### Alarms
- Full **CRUD** with swipe-to-delete + **undo**, tap-to-edit, and an inline enable/disable switch per card.
- Rich alarm editor: **AM/PM-or-24h-aware time picker**, repeat-day mask, custom label, **wake-challenge
  picker** (QR vs object photo) with object capture, **snooze** (on/off, max count, per-snooze minutes),
  **ring volume 1–100%**, and a **gradual-wake fade-in** — every one of these plumbed all the way to a
  firmware byte.
- **Per-alarm sync status** (On clock / Pending sync / Sync failed) computed from a **stable FNV-1a
  `syncHash`** over exactly the 8 wire-relevant bytes — chosen over `Object.hash` specifically because it
  must be **stable across app runs** to detect "the clock hasn't received this edit yet." Cosmetic fields
  (label, object) are deliberately excluded so they don't trigger a needless re-sync.
- **5 hardware slots enforced centrally** in the bloc (the 6th add is rejected with a message), closing
  duplicate-tap/race gaps that a UI-only guard would miss.
- **Versioned persistence**: alarms serialize into a v2 storage envelope in `SharedPreferences` with a
  **migration path from the legacy v1 bare-list format**, so old installs upgrade cleanly.

### Wake challenge & dismissal
- **On-device object-photo challenge** — photograph a chosen morning-routine object; recognition runs
  locally via **Google ML Kit image labeling (no network)**, with a saved text reminder of what to find.
- **Printed QR backup code** — camera scan on the ringing screen, verified against the stored token.
- **Single app-wide backup code** — reworked from per-alarm keys to **one static 8-byte HMAC-SHA256 token**
  that dismisses **any** protected alarm. The elegant part: it needed **zero firmware changes** — the app
  just pushes the same token to every slot via `0x07`, so the clock's per-slot `memcmp` passes everywhere.
  Rotation was intentionally disabled (`deleteKey` is a no-op) so a printed paper code stays valid forever.
- **One Print button** in the Clock tab's Backup Code section — consolidated from scattered per-card /
  editor buttons, and the redundant in-app "scan backup code" button was removed.
- **Task-aware ringing dismissal** (`RingingDismissal`) — a single source of truth that renders the correct
  action — **Dismiss / Take Photo / Scan QR** — based on the alarm's challenge, on **three surfaces at
  once**: a global banner over every tab, the large Home ring card, and the Alarms-tab card (which flips to
  an error tint/border + a "Ringing now" pill so it's unmistakable). One helper guarantees the label, icon,
  and behaviour can never drift between surfaces.
- **Anti-cheat gating**: the backup-QR bypass for object alarms unlocks only **3 minutes** after the ring
  starts (with a live countdown), and there is deliberately **no free "dismiss anyway"** escape hatch.
- **Dismissal history** — records method, label, and time for every dismissal.

### Timers
- Create timers from a **glass wheel-picker sheet**; live countdown mirrors that **tick every second** (and
  the ticker is torn down when no timers exist, so an idle tab costs nothing).
- Stop/cancel dispatches `0x0B` to actually **silence a finished-timer chime / cancel a running countdown**
  on the hardware — previously the ✕ only cleared the phone's list while the clock kept sounding to its 60 s
  timeout.

### Clock control (Clock tab)
- Device header with live online/offline pill.
- **Display settings** synced to hardware (`0x06`): auto-dim via light sensor, plus sleep-mode start/end
  with minute precision.
- **Bluetooth controls**: reconnect to the *remembered* device specifically (not a generic rescan that
  would break auto-reconnect), and a confirm-guarded forget-device.
- **Synchronization panel**: last-sync timestamp, "N of M alarms synced", active-timer count, and a manual
  "Sync Time, Alarms & Settings" action.

### Sync & connectivity engine
- **On-demand, foreground-only BLE by design** — the clock is autonomous, so there's deliberately no
  background BLE and no perpetual reconnect loop; just bounded auto-connect retries on app open.
- **Auto-sync** on connect and on any alarm change, **coalesced** through a `clockSyncInProgress`
  notifier (≤2 attempts with a settle delay) so rapid taps/edits collapse into one clean sync instead of
  stacking.
- **Feedback discipline**: a success/failure card shows only for user-initiated syncs; background syncs are
  silent. Reworked so a single owner emits the one failure card (no more double "sync failed" cards, no
  action-queue lag).
- **Time sync** transmits local-epoch seconds (UTC + tz offset) so the RTC-less clock face and alarm
  matching stay aligned and the **phone owns DST**.
- **AlarmBloc processes events strictly one-at-a-time** (a sequential transformer) — a deliberate choice,
  because concurrent handling would clobber the sync/delete bookkeeping.

### Backup notifications
- Enabled alarms are **mirrored to local notifications** (scheduled from `AlarmBloc`, timezone-aware) as a
  safety net, so a phone-side alarm still fires even if the clock is unreachable — while being clear they
  can't run the scan/QR dismissal.

### Onboarding, pairing & app routing
- First-run onboarding → pairing screen with **live BLE scan** and auto-connect to the first "WG Clock".
  *(Onboarding flow + pairing-progress UI built by Mekyle Alam via the merged `onboarding` branch, with
  additional feature/idea and UI input; since reworked.)*
- **Skip-pairing** (persisted `setupSkipped`) so the app opens **fully offline** — alarms still save locally
  and fire via backup notifications — with **Settings → Advanced → Connect a Clock** as the reversible way
  back in.
- **Three-way declarative home routing** (paired / skipped / needs-setup) driven off `rememberedDeviceId`,
  `setupSkipped`, and `hasSeenOnboarding`, keeping the widget tree and persisted prefs from ever disagreeing
  about whether a clock is paired.
- **Developer mode / simulated clock** — a full `SimulatedBleRepositoryImpl` lets the entire connected UI
  (sync, ringing, dismissal) be exercised **without any hardware**, swappable at runtime in debug builds.

### Settings
- **Appearance** (light/dark/system theme + accent color), **Time** (a 24-hour toggle routed through one
  `AlarmTimeUtils.formatTime` helper so every clock face in the app stays consistent), **wake-challenge
  default** for new alarms, **backup-notifications** toggle, plus Data / General / Advanced sections with
  Connect-a-Clock / Unpair / Disconnect-Simulated shown contextually (exactly one at a time).

### UI / design system
- A cohesive **"Liquid Glass" design system** (`glass.dart` + `wake_widgets.dart`: glass cards,
  sections, settings rows, status pills, primary/secondary buttons, empty states) — **fully theme-driven in
  both light and dark**, a custom floating tab bar, and iOS-style rubber-band scrolling (no Android glow).
- **Banner overlay fix** — diagnosed a doubled status-bar inset (banner + tab each painting their own
  SafeArea) and reworked banners to **float over content in a Stack** under a single SafeArea, reserving
  zero layout height, with opaque blended backgrounds so nothing bleeds through.
- **Non-queueing snackbars** (`app_snackbar.dart`) that clear the queue first, so feedback never lags behind
  a stale card.

### Reliability hardening (production audit — all resolved)
- Fixed a **critical time-sync protocol mismatch** (3-byte → correct 4-byte epoch) that would have broken
  the standalone clock schedule; added the **missing alarm persistence**; wired the **real `0x09` dismissal
  packet** (was a placeholder, so the clock never actually stopped); implemented the previously-empty
  **timer quick action**; and removed non-functional placeholder Developer settings.

### iOS / App Store (TestFlight)
- Shipped a **first beta to TestFlight**: rebranded bundle id `com.aaronhua.wakeguard`, versioned
  `0.1.0+N` with the build-number-bump discipline App Store Connect requires.
- Resolved a real **App Store rejection (ITMS-90683)** by adding the missing
  `NSLocationAlwaysAndWhenInUseUsageDescription` purpose string, and correctly answered **export compliance**
  (HMAC-authentication-only → exempt).

### Repo, testing & docs
- Migrated the project to `github.com/cowfollowdog/WakeGuard.git` with **full commit history preserved** and
  origin repointed.
- **39 passing automated tests** guarding the load-bearing pieces — the BLE framing round-trip, the `0x02`
  payload encoding, sync-status/hash logic, storage-envelope migration, light-theme text color, and the
  ringing-dismissal action mapping — with `flutter analyze` kept clean throughout.
- Maintained a `CLAUDE.md` engineering brief and a structured per-fact memory so the project stays
  understandable across sessions.

---

*This log reflects the app as of 2026-07-08 (first beta, v0.1.0). For engineering detail see `CLAUDE.md`;
for the product/protocol spec see `README.md` and `Smart BLE Alarm Specification.md`.*
