# WakeGuard - Aaron Hua Update Log

Last updated: 2026-07-13

## Purpose

This file records the WakeGuard work built and directed by Aaron Hua (GitHub `cowfollowdog`). It complements
`PROJECT_LOG.md` with a focused record of Aaron's contributions, and — like `MEKYLE_UPDATE_LOG.md` — is a
first-person contribution log. Where possible, entries are grounded in the git history so the record stays
verifiable: Aaron authored **38 of the 49 commits** across all branches and every core-engineering file.

## Project Origin And Concept

- Originated WakeGuard's core product concept: an **autonomous alarm clock for people with narcolepsy /
  sleep inertia** that cannot be silenced with a tap — dismissal requires a physical wake challenge so the
  user actually gets up. (Summer project at UT Austin; the app's burnt-orange accent `#BF5700` is UT's.)
- Defined the **system split**: a self-sufficient Arduino + HM-10 clock that keeps time and rings on its
  own, plus a Flutter companion app that only configures it — the phone is never a dependency for the alarm.
- Authored the **initial app outline and specification** (git: "added specification for agent", "app outline
  made", "ui improvements", 2026-06-30 / 07-01) that later app-side work built on top of.

## Hardware And Physical Build

- Designed and built the **physical clock**: wiring (buzzer on D9 -> GND) and assembly.
- Performed the hands-on **buzzer diagnosis** (cleaned contacts, reflashed, confirmed wiring) that isolated
  a hardware-vs-firmware question, plus three standalone diagnostic sketches (steady-DC, `tone()` 2 kHz,
  bit-bang ~1 kHz) as a clean code-vs-hardware discriminator.

## Firmware (Arduino / HM-10)

- Authored the **autonomous clock firmware** (`arduino/WakeGuardClock/WakeGuardClock.ino`; git first-add:
  `cowfollowdog`, 2026-07-06).
- **Software timekeeping with drift calibration** (no RTC): keeps time in software and compensates for
  ceramic-resonator drift across long offline stretches.
- **EEPROM persistence** of alarms, settings, and dismissal tokens (magic-byte layout) so the clock survives
  power loss and keeps ringing with no phone present.
- **On-device secured dismissal**: each protected alarm stores an 8-byte token accepted only on a
  constant-`memcmp` match; the buzzer keeps sounding on a wrong token — the wake challenge is enforced in
  hardware, not just the app.

## BLE Protocol (app <-> firmware)

- Designed and implemented a **framed serial-over-BLE protocol** end to end — the same wire format written
  twice, once in Dart (`ble_payloads.dart`; git first-add on Aaron's UT-Austin machine, 2026-07-01) and once
  in Arduino C++, proven to agree byte-for-byte.
- Frame format `SOF · cmd · len · payload · XOR-checksum · EOF` with a uniform escape scheme, 20-byte MTU
  chunking for the HM-10, and a write mutex serializing concurrent writes on the single RX/TX characteristic.
- A **14-command instruction set** (time sync, alarm upsert/delete, sync brackets, clock settings, token
  store, dismiss, timer set/stop), a clock->app ring handshake (`0x08`/`0x88`), dismiss ack (`0x89`), and an
  error channel (`0xFF`).
- **Length-guarded, forward/backward-compatible frame evolution**: grew the `0x02` alarm frame 5 -> 9 bytes
  (snooze count/length, volume, gradual-wake fade) so newer app and older firmware still interoperate.

## Alarms And Wake Challenge

- Alarm CRUD with swipe-to-delete + undo, inline enable switch, and a rich editor (time picker, repeat mask,
  snooze, ring volume, gradual-wake fade) — each plumbed to a firmware byte.
- **Per-alarm sync status** from a stable FNV-1a `syncHash` over exactly the 8 wire-relevant bytes (stable
  across app runs so "not yet synced" is detectable); 5 hardware slots enforced centrally in the bloc.
- **Wake-challenge design**: on-device object-photo verification (Google ML Kit, no network) as the primary
  experience, with a printed QR backup; the decision to gate the item-alarm backup to 3 minutes and have
  **no** free "dismiss anyway".
- **Single global backup code**: reworked from per-alarm keys to one static 8-byte HMAC-SHA256 token that
  dismisses any protected alarm with zero firmware changes (same token pushed to every slot via `0x07`).
- **Task-aware ringing dismissal** (`RingingDismissal`): one source of truth rendering Dismiss / Take Photo /
  Scan QR consistently across banner, Home card, and Alarms card.

## Timers, Sync And Connectivity

- Timers with a live per-second countdown; stop dispatches `0x0B` to actually silence the hardware chime.
- Authored the **sync/connectivity engine** (`clock_sync.dart`; git first-add: `cowfollowdog`, 2026-07-06):
  **on-demand, foreground-only BLE by design**, coalesced auto-sync via `clockSyncInProgress`, single-owner
  success/failure feedback, epoch time-sync (phone owns DST), and a strictly sequential AlarmBloc transformer.
- **Backup notifications**: enabled alarms mirrored to local notifications as a safety net when the clock is
  unreachable.

## App Foundation, Routing And Design System

- **Three-way declarative home routing** (paired / skipped / needs-setup) off `rememberedDeviceId`,
  `setupSkipped`, `hasSeenOnboarding`; skip-pairing so the app opens fully offline; developer-mode simulated
  clock (`SimulatedBleRepositoryImpl`) exercising the whole connected UI without hardware.
- The **Liquid Glass design foundation** (`glass.dart` + `wake_widgets.dart`), fully theme-driven in light
  and dark, and the four-tab navigation and banner-overlay model.

## Reliability Hardening (Production Audit)

- Fixed a critical time-sync mismatch (3-byte -> 4-byte epoch) that would have broken the standalone
  schedule; added missing alarm persistence; wired the real `0x09` dismissal packet (was a placeholder so
  the clock never stopped); implemented the empty timer quick action; removed placeholder Developer settings.

## Repo, Testing And Docs

- Migrated the project to `github.com/cowfollowdog/WakeGuard.git` with full history preserved.
- The automated test suite guarding the load-bearing pieces (BLE framing round-trip, `0x02` encoding,
  sync-hash logic, storage migration, ringing-dismissal mapping) with `flutter analyze` kept clean.
- Authored the original `PROJECT_LOG.md` (2026-07-08), `README.md`, the specification, and the `CLAUDE.md`
  engineering brief.

## Release Support

- Contributed to release planning and TestFlight troubleshooting, including the App Store rejection
  (ITMS-90683) fix and the export-compliance answer (HMAC-authentication-only -> exempt); shipped the first
  beta under the `com.aaronhua.wakeguard` identity.

## Note On AI Assistance

Like the rest of the project, much of the code was generated with AI assistants (Claude Code / Codex) under
Aaron's direction. The contributions above reflect the design, architecture, hardware, protocol, and product
decisions Aaron made and directed — the human, non-AI-generated work — plus the physical build and firmware.

## Summary

Aaron Hua originated WakeGuard and authored the majority of the codebase (38/49 commits) and its entire
hardware and firmware half: the physical clock, the autonomous Arduino firmware, the byte-for-byte BLE
protocol, the sync engine, the alarm and wake-challenge systems, the backup-code security design, the app
foundation and Liquid Glass design system, and the production hardening. This is the load-bearing
engineering that makes the clock work without a phone, and it should be preserved as part of WakeGuard's
project record.
