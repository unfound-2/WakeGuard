# Pre-Release Blockers — Shortlist

> The **must-fix** subset only. Two goals: (A) pass Apple App Store review, (B) core
> functionality works. Each row points back to `Production Pre-Release Audit Spec.md`
> by its tag (§13 `file:line`, §12 question #, §7) — open the spec for detail.
> Priority: 🔴 blocker · 🟠 high · 🟡 conditional.
> Status: ✅ done · ⏳ deferred (needs a decision) · ⬜ not started.

---

## Progress — session 2026-07-09

**5 tasks completed** (verified: `plutil -lint` OK on all 3 plists, `dart analyze` clean on both edited files):

1. ✅ **Notification TZ fallback** — `notification_service.dart` no longer leaves `tz.local` at UTC on IANA lookup failure; falls back to a fixed `Etc/GMT±N` zone from the phone's UTC offset.
2. ✅ **Bloc handler signatures** — `_onAddOrUpdateAlarm` / `_onDeleteAlarm` now `Future<void>` (correctness/lint hardening — bloc already awaited the runtime future, so no behaviour change; `_sequential()` transformer untouched).
3. ✅ **Privacy manifest** — created `ios/Runner/PrivacyInfo.xcprivacy` **and** wired it into `project.pbxproj` (file-ref + build-file + group + Copy-Bundle-Resources) so it actually ships.
4. ✅ **Export compliance** — added `ITSAppUsesNonExemptEncryption = false` to `Info.plist`.
5. ✅ **Git hygiene** — `git rm --cached build/ios/SourcePackages/workspace-state.json` (staged, file kept on disk; repo-root `.gitignore` already had `/build/`). *Not yet committed.*

**Corrected during the work:**
- ❌→n/a **Podfile.lock (was A-🔴):** stale lead. `audioplayers_darwin` and `wakelock_plus` **are** in the current `Podfile.lock` with matching checksums. Not a blocker.

**Still open / needs your decision:**
- ⏳ **Firmware `tryDismiss` no-token accept (B-🔴):** NOT auto-changed. Flipping it risks a ring that can't be stopped (physical button only *snoozes* secured alarms). Real fix is a coordinated app+firmware change. See note below the tables.
- Confirm the two **judgement calls** in `PrivacyInfo.xcprivacy`: (a) it declares **no** collected-data types — decide whether IP-based weather counts as Coarse-Location collection for you; (b) `ITSAppUsesNonExemptEncryption=false` assumes HMAC-only (exempt).

---

## A. Apple App Store review

| P | Ref (in Spec) | Item | Status |
|---|---|---|---|
| 🔴 | §13 iOS · §12 #4 | `Runner/PrivacyInfo.xcprivacy` **absent** — privacy manifest now required (camera / BLE / IP-geolocation + required-reason APIs). Rejection risk. | ✅ created + wired |
| 🔴 | §12 #6 · §13 iOS | `audioplayers` / `wakelock_plus` in `pubspec.lock` but ~~absent from `Podfile.lock`~~ — **both present in current `Podfile.lock`**; lead was stale. | ✅ n/a (verified) |
| 🟠 | §13 iOS · §12 #3 | `ITSAppUsesNonExemptEncryption` **absent** — resolves the export-compliance prompt (HMAC-only ⇒ exempt). Add key or answer each upload. | ✅ key added (`false`) |
| 🟠 | §13 iOS · §12 #5 | Runner has **no explicit `CODE_SIGN_STYLE`** (`iPhone Developer` identity) — set up distribution signing/provisioning. | ⬜ submitter-specific |
| 🟡 | §13 iOS · §12 #8 | `UIBackgroundModes` absent vs foreground ring — only matters **if** Phone Alarm / Dedicated Clock ship enabled. Decide scope. | ⬜ scope decision |
| 🟡 | §12 #7 · §13 Android | Android debug-signing + `applicationId` mismatch — only if **Android also ships**. | ⬜ if Android ships |
| 🟡 | §13 Assets | `build/ios/SourcePackages/workspace-state.json` tracked in git despite `/build/` ignore — hygiene. | ✅ untracked (staged) |

---

## B. Core functionality (main flows work)

| P | Ref (in Spec) | Item | Status |
|---|---|---|---|
| 🔴 | §13 Firmware `WakeGuardClock.ino:943-960` | `tryDismiss` accepts dismissal when alarm is `qrRequired` but has **no stored token** (`ok=true`) — defeats the wake-challenge on the core promise. | ⏳ needs decision |
| 🔴 | §13 `notification_service.dart:34-40` | Timezone resolution failure falls back to **UTC** → backup alarms fire at the wrong wall-clock. The backup layer is the safety net. | ✅ fixed |
| 🔴 | §13 `alarm_bloc.dart:314,393` | `_onAddOrUpdateAlarm` / `_onDeleteAlarm` are `void async` under `asyncExpand` — **not awaited**, can break the sequential persist/sync ordering. | ✅ hardened (`Future<void>`) |
| 🟠 | Task 1 report §5 #1 | XOR-only checksum **+ app ignores `0xFF` CMD_ERROR** (`main_screen.dart:137-145`) — a corrupted-but-valid frame writes wrong clock state, undetected. | ⬜ not started |
| 🟠 | §13 `alarm_bloc.dart:459-473` | `_onSyncAlarmsToDevice` early-returns on the **first delete failure** — remaining alarms/deletes silently unsynced. | ⬜ not started |
| 🟠 | §13 `item_scan_screen.dart:44,167` | 3-minute backup-QR gate keys solely on `ringingSince` and hides entirely if `ringingAlarmId != alarm.id` — anti-cheat/usability edge. | ⬜ not started |
| 🟡 | §13 `dedicated_clock_screen.dart:107-122` | One-time alarm **re-fires every day**; two alarms in the same minute → only the first rings. Only if **Dedicated Clock ships**. | ⬜ if DC ships |

---

### ⏳ Firmware `tryDismiss` — why it's deferred, and the options

Current (`WakeGuardClock.ino:951-957`):
```c
if (!ringSecured)                               ok = true;   // button-dismissal alarm
else if (slot >= 0 && alarms[slot].hasToken)    ok = (memcmp(alarms[slot].token, token, 8) == 0);
else                                            ok = true;   // secured but no key on record — accept
```
The last branch is the hole: a secured alarm with no stored token accepts **any** `0x09` (incl. the all-zero unsecured-dismiss frame). But a blind flip to `ok = false` **strands the user** — `buttonOnRing()` only *snoozes* secured alarms, so the ring could never be stopped.

Options (pick one — I did NOT apply any):
- **(a) Coordinated fix (correct):** guarantee the token is present before a secured alarm can ring — firmware refuses/re-requests until it has the `0x07` token; app already always sends it. Touches both sides + the BLE contract (CLAUDE.md §11 / ble-alarm-payload-is-fixed).
- **(b) Minimal mitigation (firmware-only):** in the no-token branch, accept only a **non-zero** token, rejecting the all-zero unsecured frame. Closes the accidental-dismiss path without stranding; still not real auth.
- **(c) Accept as-is:** treat the missing-token case as too rare to matter and keep the anti-stranding valve.

---

### Explicitly NOT on this list (by design — do not "fix")
- §13 `secure_key_datasource.dart:42-50` global static token + no-op `deleteKey` — **accepted trade-off** (CLAUDE.md §6/§11: "one code for all alarms"). Not a bug.
- §13 `ble_payloads.dart:22-25` local-epoch time sync — app ↔ firmware **agree** (Task 1 verified). Convention, not a defect.
- AlarmBloc sequential transformer — **do not change** (CLAUDE.md §11).
