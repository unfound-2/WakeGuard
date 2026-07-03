import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var bluetoothService: BluetoothClockService
    let onConnected: () -> Void
    let onSkipForDevelopment: () -> Void

    var body: some View {
        WakeGuardBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        statusCard
                        actionCard
                        discoveredDevices
                    }
                    .padding(20)
                }
                .background(Color.clear)
                .navigationTitle("Pair Clock")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .onChange(of: bluetoothService.connectedDevice) { _, connectedDevice in
            if connectedDevice != nil {
                onConnected()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            WakeGuardLogoMark(size: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text("Connect WakeGuard")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(theme.palette.text)

                Text("Pair with your physical clock to synchronize alarms, timers, display settings, and time calibration.")
                    .font(.body)
                    .foregroundStyle(theme.palette.secondaryText)
                    .lineSpacing(4)
            }
        }
        .padding(.top, 12)
    }

    private var statusCard: some View {
        WakeCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bluetoothService.status.title)
                        .font(.headline)
                        .foregroundStyle(theme.palette.text)

                    Text(bluetoothService.status.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isInProgress {
                    ProgressView()
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                        .accessibilityLabel(bluetoothService.status == .scanning ? "Searching" : "Connecting")
                }
            }
        }
    }

    private var actionCard: some View {
        WakeCard {
            VStack(spacing: 14) {
                WakePrimaryButton(title: searchButtonTitle, systemImage: "magnifyingglass") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    bluetoothService.startSearch()
                }
                .disabled(bluetoothService.status == .scanning)
                .opacity(bluetoothService.status == .scanning ? 0.72 : 1)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSkipForDevelopment()
                } label: {
                    VStack(spacing: 4) {
                        Text("Skip For Now")
                            .font(.subheadline.weight(.semibold))

                        Text("Temporary development bypass only. Bluetooth remains disconnected.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.palette.mutedText)
                .background(theme.palette.elevatedSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHint("Bypasses pairing without creating a fake Bluetooth connection.")
            }
        }
    }

    @ViewBuilder
    private var discoveredDevices: some View {
        if bluetoothService.discoveredDevices.isEmpty {
            EmptyStateView(
                title: "No clocks yet",
                message: "Tap Search For Clock while your HM-10 module is powered and nearby.",
                systemImage: "dot.radiowaves.left.and.right"
            )
        } else {
            WakeSection("Nearby Clocks", subtitle: "Choose the device that matches your WakeGuard hardware.") {
                VStack(spacing: 12) {
                    ForEach(bluetoothService.discoveredDevices) { device in
                        WakeCard {
                            HStack(spacing: 14) {
                                Image(systemName: "alarm.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                                    .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.displayName)
                                        .font(.headline)
                                        .foregroundStyle(theme.palette.text)

                                    Text(device.signalDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(theme.palette.mutedText)
                                }

                                Spacer()

                                Button("Connect") {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    bluetoothService.connect(to: device)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchButtonTitle: String {
        bluetoothService.status == .scanning ? "Searching..." : "Search For Clock"
    }

    private var isInProgress: Bool {
        switch bluetoothService.status {
        case .scanning, .connecting:
            return true
        default:
            return false
        }
    }

    private var statusSymbol: String {
        switch bluetoothService.status {
        case .connected: "checkmark.circle.fill"
        case .scanning, .connecting, .syncing: "arrow.triangle.2.circlepath"
        case .failed, .bluetoothUnavailable: "exclamationmark.triangle.fill"
        case .idle, .disconnected: "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch bluetoothService.status {
        case .connected: theme.palette.success
        case .failed, .bluetoothUnavailable: theme.palette.warning
        case .scanning, .connecting, .syncing: theme.mode == .dark ? theme.palette.primary : theme.palette.secondary
        case .idle, .disconnected: theme.palette.mutedText
        }
    }
}
