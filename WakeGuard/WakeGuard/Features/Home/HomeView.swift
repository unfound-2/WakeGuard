import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var bluetoothService: BluetoothClockService
    @State private var showingAlarmEditor = false

    var body: some View {
        WakeGuardBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    connectionOverview
                    metricsGrid
                    quickActions
                    recentActivity
                }
                .padding(20)
            }
        }
        .navigationTitle("WakeGuard")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAlarmEditor) {
            AlarmEditorView(alarm: nil)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            WakeGuardLogoMark(size: 58)

            VStack(alignment: .leading, spacing: 5) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.palette.mutedText)
                }

                Text("Your clock at a glance")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.palette.text)
            }

            Spacer()
        }
    }

    private var connectionOverview: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(connectionTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.palette.text)

                        Text(bluetoothService.status.detail)
                            .font(.subheadline)
                            .foregroundStyle(theme.palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    StatusPill(title: bluetoothService.status.title, systemImage: connectionSymbol, color: connectionColor)
                }

                HStack(spacing: 12) {
                    WakeSecondaryButton(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        bluetoothService.syncNow(alarmStore: alarmStore)
                    }

                    NavigationLink {
                        ClockView()
                    } label: {
                        Label("Controls", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.palette.text)
                    .background(theme.palette.elevatedSurface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.palette.divider, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Device",
                value: bluetoothService.connectedDevice?.displayName ?? "Not paired",
                systemImage: "alarm.fill"
            )
            MetricTile(
                title: "Next Alarm",
                value: nextAlarmText,
                systemImage: "bell.badge.fill"
            )
            MetricTile(
                title: "Active Timer",
                value: alarmStore.activeTimer?.formattedRemaining ?? "None",
                systemImage: "timer"
            )
            MetricTile(
                title: "Last Sync",
                value: lastSyncText,
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var quickActions: some View {
        WakeSection("Quick Actions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(title: "Create Alarm", systemImage: "plus.circle.fill") {
                    showingAlarmEditor = true
                }

                QuickActionButton(title: "Start Timer", systemImage: "timer.circle.fill") {
                    alarmStore.addTimer(title: "Focus Timer", duration: 25 * 60)
                }

                QuickActionNavigationButton(title: "Scan QR Code", systemImage: "qrcode.viewfinder") {
                    ScannerView(initialMode: .qrCode)
                }

                QuickActionNavigationButton(title: "Clock Controls", systemImage: "slider.horizontal.3") {
                    ClockView()
                }
            }
        }
    }

    private var recentActivity: some View {
        WakeSection("Recent Activity") {
            WakeCard {
                VStack(alignment: .leading, spacing: 12) {
                    ActivityRow(
                        title: "Synchronization",
                        subtitle: bluetoothService.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No sync completed yet",
                        systemImage: "arrow.triangle.2.circlepath"
                    )

                    Divider().overlay(theme.palette.divider)

                    ActivityRow(
                        title: "Protected dismissal",
                        subtitle: "QR dismissal is ready when alarms require it",
                        systemImage: "qrcode"
                    )
                }
            }
        }
    }

    private var nextAlarmText: String {
        guard let nextAlarm = alarmStore.nextAlarm else {
            return "None"
        }
        return nextAlarm.formattedTime(uses24HourClock: settingsStore.clockSettings.uses24HourClock)
    }

    private var lastSyncText: String {
        bluetoothService.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "Never"
    }

    private var connectionTitle: String {
        bluetoothService.connectedDevice?.displayName ?? "Clock not connected"
    }

    private var connectionSymbol: String {
        bluetoothService.isConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var connectionColor: Color {
        bluetoothService.isConnected ? theme.palette.success : theme.palette.warning
    }
}

private struct QuickActionButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            quickActionContent
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private var quickActionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(theme.palette.text)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(theme.palette.surface.opacity(theme.mode == .dark ? 0.82 : 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.palette.divider, lineWidth: 1)
        }
    }
}

private struct QuickActionNavigationButton<Destination: View>: View {
    let title: String
    let systemImage: String
    let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            QuickActionButton(title: title, systemImage: systemImage) {}
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
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
            }

            Spacer()
        }
    }
}

