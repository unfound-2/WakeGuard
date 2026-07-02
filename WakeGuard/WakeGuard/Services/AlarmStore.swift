import Combine
import Foundation

final class AlarmStore: ObservableObject {
    private let alarmsKey = "wakeguard.alarms"
    private let timersKey = "wakeguard.timers"
    private let defaults: UserDefaults

    @Published var alarms: [Alarm] {
        didSet { saveAlarms() }
    }

    @Published var timers: [WakeTimer] {
        didSet { saveTimers() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alarms = Self.decode([Alarm].self, from: defaults.data(forKey: alarmsKey)) ?? []
        timers = Self.decode([WakeTimer].self, from: defaults.data(forKey: timersKey)) ?? []
    }

    var nextAlarm: Alarm? {
        alarms
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.hour == rhs.hour {
                    return lhs.minute < rhs.minute
                }
                return lhs.hour < rhs.hour
            }
            .first
    }

    var activeTimer: WakeTimer? {
        timers.first(where: \.isRunning)
    }

    func addAlarm(hour: Int, minute: Int, label: String, repeatDays: Set<Weekday>, requiresQRCode: Bool) {
        alarms.append(
            Alarm(
                hour: hour,
                minute: minute,
                label: label.isEmpty ? "Wake up" : label,
                isEnabled: true,
                repeatDays: repeatDays,
                requiresQRCode: requiresQRCode
            )
        )
    }

    func updateAlarm(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else {
            return
        }
        alarms[index] = alarm
    }

    func toggleAlarm(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else {
            return
        }
        alarms[index].isEnabled.toggle()
    }

    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
    }

    func duplicateAlarm(_ alarm: Alarm) {
        var copy = alarm
        copy.id = UUID()
        copy.label = "\(alarm.label) copy"
        copy.lastSyncedAt = nil
        alarms.append(copy)
    }

    func markAlarmsSynced(at date: Date = .now) {
        for index in alarms.indices {
            alarms[index].lastSyncedAt = date
        }
    }

    func addTimer(title: String, duration: TimeInterval) {
        timers.append(
            WakeTimer(
                title: title.isEmpty ? "Timer" : title,
                duration: duration,
                remaining: duration,
                isRunning: false
            )
        )
    }

    func toggleTimer(_ timer: WakeTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else {
            return
        }
        timers[index].isRunning.toggle()
    }

    func cancelTimer(_ timer: WakeTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else {
            return
        }
        timers[index].isRunning = false
        timers[index].remaining = timers[index].duration
    }

    func deleteTimer(_ timer: WakeTimer) {
        timers.removeAll { $0.id == timer.id }
    }

    func resetLocalData() {
        alarms.removeAll()
        timers.removeAll()
    }

    private func saveAlarms() {
        defaults.set(Self.encode(alarms), forKey: alarmsKey)
    }

    private func saveTimers() {
        defaults.set(Self.encode(timers), forKey: timersKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

final class SettingsStore: ObservableObject {
    private let settingsKey = "wakeguard.clockSettings"
    private let defaults: UserDefaults

    @Published var clockSettings: ClockSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(ClockSettings.self, from: data) {
            clockSettings = decoded
        } else {
            clockSettings = ClockSettings()
        }
    }

    func reset() {
        clockSettings = ClockSettings()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(clockSettings), forKey: settingsKey)
    }
}
