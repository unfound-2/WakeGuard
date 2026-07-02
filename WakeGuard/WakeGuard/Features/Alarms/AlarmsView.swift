import SwiftUI

struct AlarmsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var editingAlarm: Alarm?
    @State private var showingNewAlarm = false

    var body: some View {
        WakeGuardBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    alarmsSection
                    timersSection
                }
                .padding(20)
            }
        }
        .navigationTitle("Alarms")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewAlarm = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Create alarm")
            }
        }
        .sheet(isPresented: $showingNewAlarm) {
            AlarmEditorView(alarm: nil)
        }
        .sheet(item: $editingAlarm) { alarm in
            AlarmEditorView(alarm: alarm)
        }
    }

    @ViewBuilder
    private var alarmsSection: some View {
        WakeSection("Alarms", subtitle: "Schedules sync to the physical clock when connected.") {
            if alarmStore.alarms.isEmpty {
                EmptyStateView(
                    title: "No alarms yet",
                    message: "Create your first WakeGuard alarm and choose whether QR dismissal is required.",
                    systemImage: "alarm"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(alarmStore.alarms) { alarm in
                        AlarmRow(alarm: alarm) {
                            alarmStore.toggleAlarm(alarm)
                        } onEdit: {
                            editingAlarm = alarm
                        } onDuplicate: {
                            alarmStore.duplicateAlarm(alarm)
                        } onDelete: {
                            alarmStore.deleteAlarm(alarm)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timersSection: some View {
        WakeSection("Timers", subtitle: "Timers can be prepared locally and synchronized with the clock.") {
            if alarmStore.timers.isEmpty {
                EmptyStateView(
                    title: "No timers configured",
                    message: "Use the dashboard quick action to create a starter timer.",
                    systemImage: "timer"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(alarmStore.timers) { timer in
                        TimerRow(timer: timer) {
                            alarmStore.toggleTimer(timer)
                        } onCancel: {
                            alarmStore.cancelTimer(timer)
                        } onDelete: {
                            alarmStore.deleteTimer(timer)
                        }
                    }
                }
            }
        }
    }
}

private struct AlarmRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settingsStore: SettingsStore
    let alarm: Alarm
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alarm.formattedTime(uses24HourClock: settingsStore.clockSettings.uses24HourClock))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(alarm.isEnabled ? theme.palette.text : theme.palette.mutedText)

                        Text(alarm.label)
                            .font(.headline)
                            .foregroundStyle(theme.palette.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                        .labelsHidden()
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                }

                HStack(spacing: 8) {
                    StatusPill(title: alarm.repeatDescription(), systemImage: "repeat", color: theme.palette.mutedText)
                    StatusPill(title: alarm.nextOccurrenceDescription(), systemImage: "calendar", color: theme.palette.mutedText)

                    if alarm.requiresQRCode {
                        StatusPill(title: "QR", systemImage: "qrcode", color: theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Edit", action: onEdit)
                    Button("Duplicate", action: onDuplicate)
                    Button("Delete", role: .destructive, action: onDelete)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct TimerRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let timer: WakeTimer
    let onToggle: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        WakeCard {
            HStack(spacing: 14) {
                Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(timer.title)
                        .font(.headline)
                        .foregroundStyle(theme.palette.text)
                    Text(timer.formattedRemaining)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(theme.palette.secondaryText)
                }

                Spacer()

                Menu {
                    Button(timer.isRunning ? "Pause" : "Start", action: onToggle)
                    Button("Cancel", action: onCancel)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.palette.mutedText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Timer actions")
            }
        }
    }
}

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var alarmStore: AlarmStore
    @State private var time: Date
    @State private var label: String
    @State private var repeatDays: Set<Weekday>
    @State private var requiresQRCode: Bool
    private let originalAlarm: Alarm?

    init(alarm: Alarm?) {
        originalAlarm = alarm

        var components = DateComponents()
        components.hour = alarm?.hour ?? 7
        components.minute = alarm?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _label = State(initialValue: alarm?.label ?? "Wake up")
        _repeatDays = State(initialValue: alarm?.repeatDays ?? [])
        _requiresQRCode = State(initialValue: alarm?.requiresQRCode ?? true)
    }

    var body: some View {
        NavigationStack {
            WakeGuardBackground {
                Form {
                    Section("Time") {
                        DatePicker("Alarm time", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                    }

                    Section("Details") {
                        TextField("Label", text: $label)
                            .textInputAutocapitalization(.words)

                        Toggle("Require QR code dismissal", isOn: $requiresQRCode)
                    }

                    Section("Repeat") {
                        ForEach(Weekday.allCases) { day in
                            Toggle(day.shortTitle, isOn: Binding(
                                get: { repeatDays.contains(day) },
                                set: { isSelected in
                                    if isSelected {
                                        repeatDays.insert(day)
                                    } else {
                                        repeatDays.remove(day)
                                    }
                                }
                            ))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(originalAlarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 7
        let minute = components.minute ?? 0
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        if var alarm = originalAlarm {
            alarm.hour = hour
            alarm.minute = minute
            alarm.label = trimmedLabel.isEmpty ? "Wake up" : trimmedLabel
            alarm.repeatDays = repeatDays
            alarm.requiresQRCode = requiresQRCode
            alarm.lastSyncedAt = nil
            alarmStore.updateAlarm(alarm)
        } else {
            alarmStore.addAlarm(
                hour: hour,
                minute: minute,
                label: trimmedLabel,
                repeatDays: repeatDays,
                requiresQRCode: requiresQRCode
            )
        }
    }
}

