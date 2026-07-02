import SwiftUI

struct ClockView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var bluetoothService: BluetoothClockService
    @State private var showingPairing = false

    var body: some View {
        WakeGuardBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    deviceHeader
                    displaySection
                    bluetoothSection
                    syncSection
                    backupCodeSection
                }
                .padding(20)
            }
        }
        .navigationTitle("Clock")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingPairing) {
            PairingView(onConnected: { showingPairing = false }, onSkipForDevelopment: { showingPairing = false })
        }
    }

    private var deviceHeader: some View {
        WakeCard {
            HStack(spacing: 14) {
                WakeGuardLogoMark(size: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bluetoothService.connectedDevice?.displayName ?? "WakeGuard Clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.palette.text)

                    Text(bluetoothService.isConnected ? "Hardware controls are available." : "Connect to apply controls to hardware.")
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.mutedText)
                }

                Spacer()

                StatusPill(
                    title: bluetoothService.isConnected ? "Online" : "Offline",
                    systemImage: bluetoothService.isConnected ? "checkmark.circle.fill" : "wifi.slash",
                    color: bluetoothService.isConnected ? theme.palette.success : theme.palette.warning
                )
            }
        }
    }

    private var displaySection: some View {
        WakeSection("Display", subtitle: "LCD controls for the physical clock.") {
            WakeCard {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Brightness", systemImage: "sun.max.fill")
                                .font(.headline)
                                .foregroundStyle(theme.palette.text)
                            Spacer()
                            Text(settingsStore.clockSettings.brightness.formatted(.percent.precision(.fractionLength(0))))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(theme.palette.mutedText)
                        }

                        Slider(value: $settingsStore.clockSettings.brightness, in: 0...1)
                            .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                            .accessibilityLabel("Display brightness")
                    }

                    Divider().overlay(theme.palette.divider)

                    Toggle("Backlight", isOn: $settingsStore.clockSettings.backlightEnabled)
                    Toggle("Automatic dimming", isOn: $settingsStore.clockSettings.automaticDimmingEnabled)
                    Toggle("Sleep schedule", isOn: $settingsStore.clockSettings.sleepScheduleEnabled)
                }
                .toggleStyle(.switch)
                .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
            }
        }
    }

    private var bluetoothSection: some View {
        WakeSection("Bluetooth", subtitle: "Pair, reconnect, or forget the clock connection.") {
            WakeCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bluetoothService.status.title)
                                .font(.headline)
                                .foregroundStyle(theme.palette.text)

                            Text(bluetoothService.status.detail)
                                .font(.subheadline)
                                .foregroundStyle(theme.palette.mutedText)
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button(bluetoothService.isConnected ? "Disconnect" : "Pair Device") {
                            if bluetoothService.isConnected {
                                bluetoothService.disconnect()
                            } else {
                                showingPairing = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                        Button("Reconnect") {
                            bluetoothService.startSearch()
                        }
                        .buttonStyle(.bordered)

                        if bluetoothService.developmentBypassPairing {
                            Button("Clear Skip") {
                                bluetoothService.clearDevelopmentBypass()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.regular)
                }
            }
        }
    }

    private var syncSection: some View {
        WakeSection("Synchronization", subtitle: "Keep phone state and hardware state aligned.") {
            WakeCard {
                VStack(alignment: .leading, spacing: 16) {
                    ActivityLine(title: "Last sync", value: bluetoothService.lastSyncDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    ActivityLine(title: "Alarm queue", value: "\(alarmStore.alarms.count) alarm\(alarmStore.alarms.count == 1 ? "" : "s")")
                    ActivityLine(title: "Timers", value: "\(alarmStore.timers.count) timer\(alarmStore.timers.count == 1 ? "" : "s")")

                    WakePrimaryButton(title: "Sync Time, Alarms, and Settings", systemImage: "arrow.triangle.2.circlepath") {
                        bluetoothService.syncNow(alarmStore: alarmStore)
                    }
                }
            }
        }
    }

    private var backupCodeSection: some View {
        WakeSection("Backup Code", subtitle: "Use printed codes only when object verification is unavailable.") {
            WakeCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Secure Backup Code")
                                .font(.headline)
                                .foregroundStyle(theme.palette.text)
                            Text("Signed backup-code generation can attach here while AI object verification remains the primary dismissal flow.")
                                .font(.subheadline)
                                .foregroundStyle(theme.palette.mutedText)
                        }
                    }

                    NavigationLink {
                        ScannerView(initialMode: .qrCode)
                    } label: {
                        Label("Open Backup Scanner", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.mode == .dark ? theme.palette.tertiary : Color.white)
                    .background(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

private struct ActivityLine: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.palette.mutedText)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.trailing)
        }
    }
}
