import Foundation

/// Panel input → the sentence you'd say to Alexa. 12-hour English times parse most reliably.
enum CommandBuilder {
    static func timer(minutes: Int, label: String? = nil) -> String {
        let label = label?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return "set a \(label.isEmpty ? "" : label + " ")timer for \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    static func alarm(at date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        "set an alarm for \(spoken(date, now: now, calendar: calendar))"
    }

    /// "6:30 am", "7 am tomorrow", "6 pm on wednesday", "6 pm on october 30".
    static func spoken(_ date: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = c.hour!, minute = c.minute!
        let time = "\(hour % 12 == 0 ? 12 : hour % 12)\(minute == 0 ? "" : String(format: ":%02d", minute)) \(hour < 12 ? "am" : "pm")"
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        switch days {
        case 0: return time
        case 1: return time + " tomorrow"
        case 2...6: f.dateFormat = "EEEE"
        default: f.dateFormat = "MMMM d"
        }
        return time + " on " + f.string(from: date).lowercased()
    }
}
