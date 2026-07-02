import SwiftUI

struct SettingsView: View {
    @AppStorage("wakeguard.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("wakeguard.hasCompletedInitialPairing") private var hasCompletedInitialPairing = false
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var bluetoothService: BluetoothClockService
    @State private var showingResetConfirmation = false
    @State private var showingAbout = false

    var body: some View {
        WakeGuardBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHeader
                    appearanceSection
                    timeSection
                    notificationsSection
                    generalSection
                    advancedSection
                    developerSection
                }
                .padding(20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Reset local WakeGuard data?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                alarmStore.resetLocalData()
                settingsStore.reset()
            }
        } message: {
            Text("This removes local alarms, timers, and settings from this phone. Hardware alarms are not modified until a future sync is performed.")
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    private var profileHeader: some View {
        WakeCard {
            HStack(spacing: 14) {
                WakeGuardLogoMark(size: 62)

                VStack(alignment: .leading, spacing: 5) {
                    Text("WakeGuard")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.palette.text)
                    Text("Autonomous smart alarm companion")
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.mutedText)
                }

                Spacer()
            }
        }
    }

    private var appearanceSection: some View {
        WakeSection("Appearance") {
            WakeCard {
                VStack(spacing: 14) {
                    Picker("Theme", selection: $theme.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Smooth animations", isOn: $settingsStore.clockSettings.animationsEnabled)
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                }
            }
        }
    }

    private var timeSection: some View {
        WakeSection("Time") {
            WakeCard {
                VStack(spacing: 14) {
                    Toggle("24-Hour Time", isOn: $settingsStore.clockSettings.uses24HourClock)
                    Toggle("Automatic Time Sync", isOn: $settingsStore.clockSettings.automaticTimeSync)
                }
                .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        WakeSection("Notifications") {
            WakeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Reminder Notifications", isOn: $settingsStore.clockSettings.notificationsEnabled)
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                    Text("Notification permission prompts should be requested at the moment reminders are enabled in a future notification service.")
                        .font(.footnote)
                        .foregroundStyle(theme.palette.mutedText)
                }
            }
        }
    }

    private var generalSection: some View {
        WakeSection("General") {
            WakeCard {
                VStack(spacing: 0) {
                    SettingsRow(title: "About WakeGuard", subtitle: "Version 1.0", systemImage: "info.circle.fill") {
                        showingAbout = true
                    }

                    Divider().overlay(theme.palette.divider)

                    SettingsRow(title: "Privacy", subtitle: "Camera and Bluetooth stay user controlled", systemImage: "hand.raised.fill") {}

                    Divider().overlay(theme.palette.divider)

                    SettingsRow(title: "Licenses", subtitle: "No third-party packages in native target", systemImage: "doc.text.fill") {}
                }
            }
        }
    }

    private var advancedSection: some View {
        WakeSection("Advanced") {
            WakeCard {
                VStack(spacing: 0) {
                    SettingsRow(title: "Factory Reset Clock", subtitle: "Requires a connected hardware protocol", systemImage: "arrow.counterclockwise.circle.fill") {}
                        .opacity(bluetoothService.isConnected ? 1 : 0.58)

                    Divider().overlay(theme.palette.divider)

                    SettingsRow(title: "Reset Local Data", subtitle: "Clear alarms, timers, and preferences on this phone", systemImage: "trash.fill") {
                        showingResetConfirmation = true
                    }

                    Divider().overlay(theme.palette.divider)

                    SettingsRow(title: "Replay Onboarding", subtitle: "Show WakeGuard introduction again", systemImage: "rectangle.stack.fill") {
                        hasSeenOnboarding = false
                        hasCompletedInitialPairing = false
                    }
                }
            }
        }
    }

    private var developerSection: some View {
        WakeSection("Developer") {
            WakeCard {
                VStack(spacing: 14) {
                    Toggle("Show diagnostics", isOn: $settingsStore.clockSettings.developerModeEnabled)
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                    if settingsStore.clockSettings.developerModeEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            DiagnosticsLine(title: "BLE status", value: bluetoothService.status.title)
                            DiagnosticsLine(title: "Bypass pairing", value: bluetoothService.developmentBypassPairing ? "Enabled" : "Disabled")
                            DiagnosticsLine(title: "Discovered clocks", value: "\(bluetoothService.discoveredDevices.count)")
                            DiagnosticsLine(title: "Firmware version", value: "Unavailable until connected")
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.palette.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.palette.mutedText)
            }
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

private struct DiagnosticsLine: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.palette.mutedText)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationStack {
            WakeGuardBackground {
                VStack(spacing: 22) {
                    WakeGuardLogoMark(size: 92)

                    VStack(spacing: 8) {
                        Text("WakeGuard")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(theme.palette.text)

                        Text("WakeGuard configures autonomous BLE alarms, syncs clock state, and prepares QR-based alarm dismissal workflows.")
                            .font(.body)
                            .foregroundStyle(theme.palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    Spacer()
                }
                .padding(28)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
