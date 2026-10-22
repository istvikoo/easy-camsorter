import Foundation

/// Календарний день зйомки (без часу).
public struct DayDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    /// Розбирає початок рядка: "2024:05:15 10:00:00" (EXIF) або "2024-05-15T10:00:00+03:00".
    public static func parse(_ text: String) -> DayDate? {
        let s = text.trimmingCharacters(in: .whitespaces)
        let chars = Array(s.prefix(10))
        guard chars.count == 10, chars[4] == chars[7], chars[4] == ":" || chars[4] == "-" else { return nil }
        guard let y = Int(String(chars[0..<4])),
              let m = Int(String(chars[5..<7])),
              let d = Int(String(chars[8..<10])) else { return nil }
        return DayDate(year: y, month: m, day: d)
    }

    public static func < (a: DayDate, b: DayDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

let ukrainianMonthsGenitive = [
    "січня", "лютого", "березня", "квітня", "травня", "червня",
    "липня", "серпня", "вересня", "жовтня", "листопада", "грудня",
]

let englishMonths = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

/// Як називати папки з датами.
public enum FolderNaming: String, CaseIterable, Identifiable, Sendable {
    /// `15 травня 2024` — як у старій версії.
    case dayMonthYear
    /// `2024-05-15 (15 травня)` — Finder сортує за хронологією.
    case isoWithName
    /// `2024/15 травня 2024` — спершу папка року.
    case yearThenDay
    /// `15 May 2024`
    case dayMonthYearEnglish
    /// `2024-05-15 (15 May)`
    case isoWithNameEnglish
    /// `2024/15 May 2024`
    case yearThenDayEnglish

    public var id: String { rawValue }

    /// Чи назви англійською.
    public var isEnglish: Bool {
        switch self {
        case .dayMonthYearEnglish, .isoWithNameEnglish, .yearThenDayEnglish: return true
        default: return false
        }
    }

    public static var ukrainianCases: [FolderNaming] { allCases.filter { !$0.isEnglish } }
    public static var englishCases: [FolderNaming] { allCases.filter(\.isEnglish) }

    /// Відносний шлях папки для дня (може містити `/`).
    public func relativePath(for d: DayDate) -> String {
        let month = isEnglish ? englishMonths[d.month - 1] : ukrainianMonthsGenitive[d.month - 1]
        switch self {
        case .dayMonthYear, .dayMonthYearEnglish:
            return "\(d.day) \(month) \(d.year)"
        case .isoWithName, .isoWithNameEnglish:
            return "\(d) (\(d.day) \(month))"
        case .yearThenDay, .yearThenDayEnglish:
            return "\(d.year)/\(d.day) \(month) \(d.year)"
        }
    }

    /// Приклад для меню вибору.
    public var example: String {
        relativePath(for: DayDate(year: 2024, month: 5, day: 15)!)
            .replacingOccurrences(of: "/", with: " / ")
    }
}
