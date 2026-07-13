# WakeGuard - Mekyle Alam Update Log

Last updated: 2026-07-13

## Purpose

This file records the WakeGuard updates, product direction, QA work, release work, and implementation
management contributed by Mekyle Alam. It is intended to complement `PROJECT_LOG.md` with a focused record
of Mekyle's app-side work and the changes he directed.

> Scope note: the entries below are Mekyle's app-side product direction, UI/UX requests, and QA, plus the
> subsystems he added (notably account/Firebase/analytics). The core product concept, hardware, firmware,
> BLE protocol, and sync engine were originated and authored by Aaron Hua. For the full picture see
> `AARON_UPDATE_LOG.md` and `CONTRIBUTORS.md`.

The updates recorded here include work Mekyle personally directed or built, product and design decisions he
made, issues he discovered through testing, release/account setup he handled, and implementation work he
directed through Codex/AI-assisted development sessions.

## Product Direction (App Side)

- Helped push the app side of WakeGuard forward as a polished product rather than a small demo.
- Supported the product goal of helping people who struggle to wake up — narcolepsy, sleep inertia, and
  alarms that are too easy to dismiss. (The core concept and the UT Austin summer project were originated by
  Aaron Hua.)
- Directed the app experience toward a stronger wake-challenge flow instead of a normal phone alarm.
- Repeatedly clarified that the app should support standalone and dedicated-clock use cases while being
  honest about iOS background and locked-screen limitations.
- Helped shape the app into a polished consumer experience with onboarding, account setup, cloud sync,
  profile creation, alarm workflows, display controls, settings, and TestFlight readiness.

## Onboarding Updates

- Requested a simpler, more modern onboarding experience inspired by stronger examples rather than generic
  "AI-looking" screens.
- Directed onboarding to explain why WakeGuard exists, including narcolepsy, sleep inertia, and why normal
  alarms can fail.
- Requested replayable onboarding so users can revisit onboarding without restarting or reinstalling the app.
- Added profile creation to the onboarding experience.
- Directed account options for Google sign-in and Apple sign-in on iOS.
- Requested a smaller "Skip for now" option for users who do not want to create an account immediately.
- Reported when onboarding did not show correctly and when buttons were not working.
- Directed fixes for onboarding flow, routing, button interaction, and startup behavior.

## Connect WakeGuard Updates

- Requested a redesigned Connect WakeGuard screen with pairing status as the hero.
- Directed clearer Bluetooth permission states and better user-facing recovery when Bluetooth permissions
  or scanning are not ready.
- Requested improved nearby-clock states so empty results feel intentional instead of broken.
- Added timeout recovery direction for searches that take too long or fail to find a clock.
- Asked for stronger copy so users understand what to do without long explanations.
- Requested subtle motion to make the pairing experience feel active and alive.

## Home Dashboard Updates

- Directed a cleaner, more modern home dashboard while keeping the existing WakeGuard visual style.
- Requested personalized greetings that use the user's name when available.
- Asked for stronger status language so the dashboard communicates clearly whether the user is protected,
  connected, synced, or needs attention.
- Helped move the home screen away from a generic layout and toward a more focused alarm/clock status hub.

## Alarm And Timer Updates

- Requested cleaner alarm cards with stronger visual styling.
- Directed secondary alarm details into edit/detail views instead of overcrowding cards.
- Requested a stronger visual split between Alarm and Timer.
- Asked to replace the floating plus button with a cleaner add pattern.
- Directed iOS-only haptics while keeping the code in Dart.
- Requested improved empty states when there are no alarms or timers.
- Requested swipe actions for alarm cards.
- Asked for alarm templates to speed up common setup flows.
- Directed a detail/edit upgrade for richer alarm configuration.
- Reported alarm-page UI issues, button problems, and behavior concerns during simulator testing.

## Display Tab Updates

- Requested a live clock preview based on the WakeGuard display.
- Directed the live preview to become the hero of the Display tab.
- Requested instant preview updates so controls visibly affect the clock preview.
- Asked to combine Theme and Accent into an Appearance section.
- Requested a visual clock-face picker instead of plain text-only options.
- Directed a polished preset strip and smaller, more refined preset cards.
- Requested improvements to sleep schedule controls.
- Asked for better display connection state messaging.
- Reported display-tab scrolling problems and Flutter layout assertion failures.

## Settings Updates

- Requested stronger polish across the Settings tab.
- Directed Profile and Account to be merged into a cleaner combined experience.
- Requested a status summary card.
- Asked to reorganize settings into fewer groups.
- Directed complex settings into detail pages so the main settings screen stays compact.
- Requested settings search.
- Asked for more compact cards and clearer hierarchy.
- Directed settings language to be simpler and more premium.

## Account, Firebase, And Cloud Updates

- Asked whether Firebase could be integrated to create an account system.
- Provided Firebase project details for WakeGuard.
- Directed the app to stay in Dart while integrating Firebase.
- Requested Google sign-in and Apple sign-in support.
- Reported the Google sign-in configuration error involving `GIDClientID`.
- Requested user profile pictures and profile names.
- Requested Firebase Storage setup for profile images.
- Directed Firebase sync for user profiles and alarm backups.
- Requested a cloud restore experience.
- Requested analytics for onboarding drop-off and failed syncs.
- Requested crash/error reporting.

*(This account/Firebase/analytics subsystem is genuinely net-new work added in Mekyle's 2026-07-13 commit.)*

## Launch, Branding, And Performance Updates

- Requested the initial loading screen be fixed to match the WakeGuard logo colors.
- Provided the WakeGuard logo PNG and asked for exact color analysis rather than approximate matching.
- Directed the splash fill/background to match the logo.
- Requested the logo be larger on the Flutter launch screen.
- Asked for an active first frame where the sun rays dim and brighten instead of relying only on a static PNG.
- Reported when the build appeared stuck on the first screen in the simulator.
- Requested startup/load-time optimization so the app moves past the first screen faster.
- Reported slow startup and button issues repeatedly until fixes were made.

## Dedicated Clock And Standalone Alarm Direction

- Asked whether the app could work as a standalone alarm on the phone without another device.
- Clarified that the desired behavior was for alarms to sound while the screen is off or the phone is locked.
- Explored iOS limitations around background execution, locked phones, and whether an alarm continues if
  the user swipes the app away.
- Directed dedicated-clock mode polish so the phone itself can act as a visible bedside clock when needed.
- Requested clear user-facing expectations around what iOS will and will not allow.

## iOS, CocoaPods, Build, And Release Work

- Reported iOS build errors where Firebase packages required iOS 15 while the target supported iOS 13.
- Requested CocoaPods updates when the sandbox was out of sync with `Podfile.lock`.
- Reported repeated Xcode and simulator errors with screenshots.
- Corrected the actual bundle identifier to `com.mekylealam.wakeguardalarm`.
- Stated and handled current TestFlight and release work.
- Directed iOS/TestFlight readiness work, including build number discipline and release-account details.
- Helped identify generated build artifacts versus real source files when old bundle IDs appeared in output.

## QA And Bug Discovery

- Provided screenshots and concrete bug reports throughout development.
- Reported onboarding not appearing.
- Reported buttons not functioning.
- Reported display-tab scrolling and layout assertion failures.
- Reported Firebase/Google sign-in failures.
- Reported splash/startup delays.
- Reported alarm page UI problems.
- Reported mismatched launch-screen colors.
- Reported CocoaPods and iOS deployment target issues.
- Verified fixes through follow-up simulator testing and additional screenshots.

## Architecture And Engineering Direction (App Side)

- Requested a more professional folder structure (the `lib/features` restructure).
- Asked for performance fixes and reduced unnecessary rebuilds.
- Asked for better state-management decisions.
- Requested production-quality Flutter patterns instead of fragile app structure.
- Requested that the existing BLE/sync logic (authored by Aaron) be reorganized into a dedicated service
  layer so UI screens stay lighter — a restructuring of Aaron's code, not new BLE engineering.
- Requested integration tests for onboarding, alarm creation, sync, and dismissal.
- Asked for broader bug/error review across the codebase and directed fixes when issues were found.

## Documentation And Attribution Updates

- Requested an attribution review of the project log.
- Requested that the log recognize his app-side contributions (onboarding, UI/UX, Firebase/account, QA, and
  release), rather than only "some UI".
- Added the corrected bundle identifier and current TestFlight/release ownership details.
- Requested a dedicated update log to preserve a focused record of his work.

> Note: an earlier revision of this section described these contributions as making Mekyle an "equal
> contributor," and the project log was rewritten accordingly in the 2026-07-13 commit. That framing was
> later reconciled against the git history (Aaron authored 38 of 49 commits and all core engineering,
> hardware, firmware, BLE protocol, and sync). See `PROJECT_LOG.md` and `CONTRIBUTORS.md` for the corrected
> record.

## Summary

Mekyle Alam's contributions to WakeGuard include app-side product direction, onboarding, UI/UX direction,
the net-new Firebase/account subsystem, profile and cloud-sync direction, alarm/display/settings/home
improvements, dedicated-clock planning, iOS/TestFlight/release work, build troubleshooting, simulator QA,
bug discovery, and repeated implementation management through Codex/AI-assisted development.

This was substantial app-side product, design, QA, and release-direction work that should be preserved as
part of WakeGuard's project record. It sits alongside — and did not author — the core engineering, hardware,
firmware, BLE protocol, and sync engine, which were Aaron Hua's (see `AARON_UPDATE_LOG.md`).
