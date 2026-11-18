import Foundation

/// When a command runs on its own, written as a phrase and read back as English:
///   every 15m · every 2h · hourly · hourly :15 · daily 09:00 · weekdays 08:30 · weekends 10:00 ·
///   mon,thu 18:00 · monthly 1 07:00
/// The scheduler turns it into launchd's StartInterval or StartCalendarInterval.
public struct Schedule: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case interval(seconds: Int)
        case calendar([CalendarEntry])
    }

    /// One launchd calendar entry. Weekday counts as launchd does: 0 is Sunday, 6 is Saturday.
    public struct CalendarEntry: Equatable, Sendable {
        public var minute: Int
        public var hour: Int?
        public var weekday: Int?
        public var day: Int?
        public init(minute: Int, hour: Int? = nil, weekday: Int? = nil, day: Int? = nil) {
            self.minute = minute; self.hour = hour; self.weekday = weekday; self.day = day
        }
    }

    /// The phrase, normalised: lowercase, single spaces.
    public let text: String
    public let kind: Kind

    public static let forms = "every 15m · every 2h · hourly · hourly :15 · daily 09:00 · weekdays 08:30 · weekends 10:00 · mon,thu 18:00 · monthly 1 07:00"
    static let dayNames: [String: Int] = ["sun": 0, "sunday": 0, "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2, "wed": 3, "wednesday": 3,
                                          "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "fri": 5, "friday": 5, "sat": 6, "saturday": 6]
    static let shortDay = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public init(_ raw: String) throws {
        let words = raw.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let text = words.joined(separator: " ")
        func bad(_ why: String = "is not understood") -> RegistryError {
            RegistryError("schedule '\(raw)' \(why)", fix: Self.forms)
        }
        guard let first = words.first else { throw bad("is empty") }
        switch first {
        case "every":
            guard words.count == 2 || words.count == 3 else { throw bad() }
            let spec = words.dropFirst().joined()
            let digits = spec.prefix { $0.isNumber }
            let unit = spec.dropFirst(digits.count)
            guard let n = Int(digits), n > 0 else { throw bad() }
            let seconds: Int
            switch unit {
            case "m", "min", "mins", "minute", "minutes": seconds = n * 60
            case "h", "hr", "hrs", "hour", "hours": seconds = n * 3600
            default: throw bad("needs a unit: m or h")
            }
            kind = .interval(seconds: seconds)
        case "hourly":
            guard words.count <= 2 else { throw bad() }
            var minute = 0
            if words.count == 2 {
                guard words[1].hasPrefix(":"), let m = Int(words[1].dropFirst()), (0...59).contains(m) else { throw bad("wants a minute as :MM") }
                minute = m
            }
            kind = .calendar([CalendarEntry(minute: minute)])
        case "daily":
            guard words.count == 2, let (h, m) = Self.time(words[1]) else { throw bad("wants a time as HH:MM") }
            kind = .calendar([CalendarEntry(minute: m, hour: h)])
        case "weekdays", "weekends":
            guard words.count == 2, let (h, m) = Self.time(words[1]) else { throw bad("wants a time as HH:MM") }
            let days = first == "weekdays" ? [1, 2, 3, 4, 5] : [0, 6]
            kind = .calendar(days.map { CalendarEntry(minute: m, hour: h, weekday: $0) })
        case "monthly":
            guard words.count == 3, let d = Int(words[1]), (1...31).contains(d), let (h, m) = Self.time(words[2]) else {
                throw bad("wants a day and a time, as monthly 1 07:00")
            }
            kind = .calendar([CalendarEntry(minute: m, hour: h, day: d)])
        default:
            guard words.count == 2, let (h, m) = Self.time(words[1]) else { throw bad() }
            var days: [Int] = []
            for part in first.split(separator: ",") {
                guard let d = Self.dayNames[String(part)] else { throw bad() }
                if !days.contains(d) { days.append(d) }
            }
            kind = .calendar(days.map { CalendarEntry(minute: m, hour: h, weekday: $0) })
        }
        self.text = text
    }

    static func time(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    static func clock(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

    /// The phrase as English: "every 15 minutes", "weekdays at 08:30", "Mon, Thu at 18:00".
    public var english: String {
        switch kind {
        case .interval(let s):
            if s % 3600 == 0 { let h = s / 3600; return "every \(h == 1 ? "hour" : "\(h) hours")" }
            let m = s / 60
            return "every \(m == 1 ? "minute" : "\(m) minutes")"
        case .calendar(let entries):
            guard let e = entries.first else { return text }
            if let d = e.day, let h = e.hour { return "monthly on the \(Self.ordinal(d)) at \(Self.clock(h, e.minute))" }
            guard let h = e.hour else { return e.minute == 0 ? "hourly" : "hourly at :" + String(format: "%02d", e.minute) }
            let at = "at \(Self.clock(h, e.minute))"
            let days = entries.compactMap(\.weekday)
            if days.isEmpty { return "daily \(at)" }
            if days.sorted() == [1, 2, 3, 4, 5] { return "weekdays \(at)" }
            if days.sorted() == [0, 6] { return "weekends \(at)" }
            return days.map { Self.shortDay[$0] }.joined(separator: ", ") + " \(at)"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    /// The next calendar occurrence after `date`; nil for an interval, whose phase only launchd knows.
    public func next(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard case .calendar(let entries) = kind else { return nil }
        return entries.compactMap { e -> Date? in
            var c = DateComponents()
            c.minute = e.minute
            if let h = e.hour { c.hour = h }
            if let w = e.weekday { c.weekday = w + 1 }
            if let d = e.day { c.day = d }
            if e.hour == nil { c.second = 0 }
            return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}
