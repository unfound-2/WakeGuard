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

enum WakeChallenge {
    static let defaultObject = "Bathroom sink"
    static let suggestedObjects = [
        defaultObject,
        "Toothbrush",
        "Coffee maker",
        "Medication",
        "Kitchen sink",
        "Front door"
    ]

    static func cleanedObjectName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultObject : trimmed
    }
}

struct ClockSettings: Codable, Equatable {
    var uses24HourClock = false
    var automaticTimeSync = true
    var animationsEnabled = true
    var notificationsEnabled = false
    var wakeChallengeObject = WakeChallenge.defaultObject
    var brightness = 0.72
    var backlightEnabled = true
    var automaticDimmingEnabled = true
    var sleepScheduleEnabled = false
    var developerModeEnabled = false

    enum CodingKeys: String, CodingKey {
        case uses24HourClock
        case automaticTimeSync
        case animationsEnabled
        case notificationsEnabled
        case wakeChallengeObject
        case brightness
        case backlightEnabled
        case automaticDimmingEnabled
        case sleepScheduleEnabled
        case developerModeEnabled
    }

    init(
        uses24HourClock: Bool = false,
        automaticTimeSync: Bool = true,
        animationsEnabled: Bool = true,
        notificationsEnabled: Bool = false,
        wakeChallengeObject: String = WakeChallenge.defaultObject,
        brightness: Double = 0.72,
        backlightEnabled: Bool = true,
        automaticDimmingEnabled: Bool = true,
        sleepScheduleEnabled: Bool = false,
        developerModeEnabled: Bool = false
    ) {
        self.uses24HourClock = uses24HourClock
        self.automaticTimeSync = automaticTimeSync
        self.animationsEnabled = animationsEnabled
        self.notificationsEnabled = notificationsEnabled
        self.wakeChallengeObject = WakeChallenge.cleanedObjectName(wakeChallengeObject)
        self.brightness = brightness
        self.backlightEnabled = backlightEnabled
        self.automaticDimmingEnabled = automaticDimmingEnabled
        self.sleepScheduleEnabled = sleepScheduleEnabled
        self.developerModeEnabled = developerModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uses24HourClock = try container.decodeIfPresent(Bool.self, forKey: .uses24HourClock) ?? false
        automaticTimeSync = try container.decodeIfPresent(Bool.self, forKey: .automaticTimeSync) ?? true
        animationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        wakeChallengeObject = WakeChallenge.cleanedObjectName(
            try container.decodeIfPresent(String.self, forKey: .wakeChallengeObject) ?? WakeChallenge.defaultObject
        )
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.72
        backlightEnabled = try container.decodeIfPresent(Bool.self, forKey: .backlightEnabled) ?? true
        automaticDimmingEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticDimmingEnabled) ?? true
        sleepScheduleEnabled = try container.decodeIfPresent(Bool.self, forKey: .sleepScheduleEnabled) ?? false
        developerModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .developerModeEnabled) ?? false
    }
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
        case .qrCode: "Backup Code"
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
