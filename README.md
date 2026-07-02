# WakeGuard

WakeGuard is a Bluetooth companion app for a compatible smart alarm clock designed for people who need more than a bedside dismiss button. Protected alarms stay active on the clock until the user completes a wake challenge in the app.

The intended flow is object-based verification: during onboarding or in Settings, the user chooses a meaningful object away from bed, such as a bathroom sink, toothbrush, coffee maker, or medication. When the alarm rings, WakeGuard guides the user to verify that object before sending the dismissal command to the clock. The current app keeps the BLE alarm, synchronization, and secure backup-code paths intact while the AI image-recognition verifier is integrated.
