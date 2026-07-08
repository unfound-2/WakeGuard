# UI & Navigation Specification

Implement the application's UI according to the following specification unless a significant technical limitation requires a minor adjustment. Maintain consistency throughout the application.

The application should feel like a polished, premium Android application with smooth animations, clean spacing, rounded components, and a modern appearance.

WakeGuard's primary dismissal experience is the **object-photo Wake Challenge**: when creating an alarm the user picks a morning-routine object away from bed, then photographs it when the alarm rings. Recognition runs **on-device** (Google ML Kit image labeling, no network). A **single app-wide printed backup code** (QR) is the sanctioned fallback and dismisses any protected alarm; for object alarms it unlocks only 3 minutes after the ring starts. An alarm may also require no challenge at all (plain Dismiss). QR is a backup, not the primary experience.

> **Implementation note (2026-07-08):** this doc is the original UI spec. Sections below that describe per-alarm QR, a Settings "wake object" picker, or backup-code Generate/View/Regenerate have been superseded — see the inline updates and `README.md` / `CLAUDE.md` for current behavior.

## Global Design Requirements

* Use the **Inter** font throughout the entire application.
* Use a dark theme with orange accents as the default theme.
* Support additional color themes through the settings menu.
* Maintain generous spacing and consistent padding.
* Use rounded cards instead of sharp edges where appropriate.
* Keep navigation intuitive and minimize the number of taps required for common actions.
* Use Material 3 components where appropriate while maintaining the application's custom visual identity.

---

# Bottom Navigation

The application should use a persistent bottom navigation bar with **four primary tabs**.

1. Home
2. Alarms
3. Clock
4. Settings

The selected tab should clearly indicate the current location.

---

# Home

The Home screen serves as the dashboard.

Display:

* Current connection status
* Current device name
* Current date and time
* Next scheduled alarm
* Active timer (if one exists)
* Last synchronization time

Provide quick action cards for:

* Create Alarm
* Start Timer
* Sync Now
* Wake Challenge
* Clock Controls

Recent activity (optional):

* Last alarm dismissed
* Last synchronization
* Firmware version

---

# Alarms

This tab manages all alarms and timers.

Sections:

## Alarms

Display all alarms as cards showing:

* Time
* Enabled state
* Repeat schedule
* Label
* Next occurrence

Support:

* Create
* Edit
* Delete
* Duplicate
* Enable/Disable

## Timers

Display all timers.

Allow:

* Create
* Edit
* Delete
* Start
* Pause
* Resume
* Cancel

Floating Action Button:

Create Alarm

---

# Clock

This tab controls the physical alarm clock.

Sections:

## Display

* Brightness
* Backlight On/Off
* Automatic Dimming
* Sleep Schedule

## Bluetooth

* Connected Device
* Signal Status
* Pair Device
* Forget Device
* Reconnect

## Synchronization

* Sync Time
* Sync Alarms
* Sync Timers
* Sync Settings
* Last Sync Status

## Backup Code

*(Current implementation)* A **single app-wide backup code** — one printed QR that dismisses **any**
protected alarm (static HMAC token). This section shows a short explanation and **one** action:

* **Print Backup Code**

There is no per-alarm code, no in-app "scan backup code" here (scanning happens on the ringing screen),
and no Generate/View/Regenerate (the code is static and shared, so rotating it would invalidate every
printed copy).

This screen controls the physical device and should not contain application preferences.

---

# Settings

Organize settings into categories.

## Appearance

* Theme
* Accent Color
* Animations

## Time

* **24-Hour (Military Time) Toggle** *(Required)*
* Automatic Time Sync

## Wake Challenge

*(Current implementation)* Settings holds only the **universal default** — whether new alarms require a
challenge (`defaultQrRequired`). The actual wake-challenge choice (object photo vs QR) and the object to
verify are configured **per alarm in the alarm editor**, not here — Settings stays universal-only.

## Notifications

* Notification Permissions
* Reminder Preferences

## General

* About
* App Version
* Privacy
* Licenses

## Advanced

* Factory Reset Clock
* Reset Local Data
* Clear Cache

## Developer (Hidden)

* BLE Logs
* Debug Information
* Firmware Version
* Packet Viewer
* Connection Diagnostics

---

# General UI Behavior

Every screen should:

* Handle loading states.
* Handle empty states.
* Handle connection failures.
* Handle synchronization errors.
* Display informative error messages.
* Display success confirmations when appropriate.

Avoid blank screens.

---

# Navigation

Navigation should remain predictable.

Users should rarely need more than three taps to reach any common feature.

Use dialogs, bottom sheets, or modal pages for quick actions instead of unnecessary full-screen pages where appropriate.

---

# Animations

Use subtle animations.

Examples:

* Card elevation
* Page transitions
* Expandable cards
* Toggle animations
* Loading indicators

Avoid excessive animation.

---

# Accessibility

Support:

* Screen readers
* Large text
* High contrast
* Large touch targets
* Keyboard navigation where applicable

---

# Responsive Design

The application should adapt cleanly across Android phone sizes.

Avoid fixed dimensions.

Prefer responsive layouts.

---

# Design Philosophy

The application should feel like a polished consumer product rather than a development tool.

Prioritize simplicity, consistency, and usability. Every screen should have a clear purpose, and every action should be discoverable without overwhelming the user. Before implementing a screen or feature, consider whether it improves the overall user experience or unnecessarily increases complexity. Favor intuitive navigation, clean visual hierarchy, and maintainable UI components.


# Existing Implementation

If any part of this UI specification has already been implemented, **do not rewrite or replace it unnecessarily**.

For each existing screen, component, or feature:

* If it already matches this specification (or is functionally equivalent), leave it unchanged.
* If it only partially matches, modify it only as much as necessary to bring it into compliance with this specification.
* If it conflicts with this specification, refactor it carefully while minimizing regressions and preserving existing functionality.
* Reuse existing widgets, components, services, and architecture whenever appropriate instead of creating duplicate implementations.

Before making changes, analyze the existing implementation to understand how it works and how your modifications may affect other parts of the application. Avoid introducing unnecessary refactoring, duplicate code, regressions, or breaking changes.

The objective is to incrementally improve and complete the existing application while keeping the codebase stable, maintainable, and consistent with this specification.
