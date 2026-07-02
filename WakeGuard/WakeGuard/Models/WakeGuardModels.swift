import Foundation

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

struct Alarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var isEnabled: Bool
    var repeatDays: Set<Weekday>
    var requiresQRCode: Bool
    var lastSyncedAt: Date?

    var isRepeating: Bool {
        !repeatDays.isEmpty
    }

    func formattedTime(uses24HourClock: Bool) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = uses24HourClock ? Locale(identifier: "en_GB") : .current
        formatter.setLocalizedDateFormatFromTemplate(uses24HourClock ? "HH:mm" : "h:mm a")
        return formatter.string(from: date)
    }

    func repeatDescription() -> String {
        guard !repeatDays.isEmpty else {
            return "Once"
        }

        let orderedDays = Weekday.allCases.filter { repeatDays.contains($0) }
        if orderedDays == [.monday, .tuesday, .wednesday, .thursday, .friday] {
            return "Weekdays"
        }
        if orderedDays == [.sunday, .saturday] {
            return "Weekends"
        }
        if orderedDays.count == Weekday.allCases.count {
            return "Every day"
        }
        return orderedDays.map(\.shortTitle).joined(separator: ", ")
    }

    func nextOccurrenceDescription(now: Date = .now) -> String {
        guard isEnabled else {
            return "Disabled"
        }

        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        if repeatDays.isEmpty {
            if hour > currentHour || (hour == currentHour && minute > currentMinute) {
                return "Today"
            }
            return "Tomorrow"
        }

        for offset in 0...7 {
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: now) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: targetDate)
            let dayMatches = repeatDays.contains { $0.rawValue == weekday }
            let timeIsFutureToday = offset > 0 || hour > currentHour || (hour == currentHour && minute > currentMinute)

            if dayMatches && timeIsFutureToday {
                if weekday == todayWeekday && offset == 0 {
                    return "Today"
                }
                return Weekday(rawValue: weekday)?.shortTitle ?? "Upcoming"
            }
        }

        return "Upcoming"
    }
}

struct WakeTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var duration: TimeInterval
    var remaining: TimeInterval
    var isRunning: Bool

    var formattedRemaining: String {
        let remainingSeconds = max(Int(remaining), 0)
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ClockSettings: Codable, Equatable {
    var uses24HourClock = false
    var automaticTimeSync = true
    var animationsEnabled = true
    var notificationsEnabled = false
    var brightness = 0.72
    var backlightEnabled = true
    var automaticDimmingEnabled = true
    var sleepScheduleEnabled = false
    var developerModeEnabled = false
}

struct ClockDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var signalStrength: Int?
    var lastSeen: Date

    var displayName: String {
        name.isEmpty ? "WakeGuard Clock" : name
    }

    var signalDescription: String {
        guard let signalStrength else {
            return "Signal unknown"
        }

        switch signalStrength {
        case -55...0: return "Excellent signal"
        case -70 ..< -55: return "Good signal"
        case -85 ..< -70: return "Weak signal"
        default: return "Very weak signal"
        }
    }
}

enum ScannerMode: String, CaseIterable, Identifiable {
    case qrCode
    case objectRecognition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qrCode: "QR Code"
        case .objectRecognition: "Object"
        }
    }

    var systemImage: String {
        switch self {
        case .qrCode: "qrcode.viewfinder"
        case .objectRecognition: "sparkle.magnifyingglass"
        }
    }
}

struct RecognitionResult: Identifiable, Equatable {
    let id = UUID()
    var mode: ScannerMode
    var label: String
    var confidence: Double
    var needsManualConfirmation: Bool
}
