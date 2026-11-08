import Foundation

// Personal fork, chantier 15: the few formats the fasting screens share, so a duration or a time reads
// the same on the Nutrition card, the Jeûne page, the lock screen and in the Coach's words.

enum FastingFormat {

    /// « 11 h 42 min », « 16 h », « 42 min »: the catalogue's existing duration forms.
    static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return String(localized: "\(m) min") }
        if m % 60 == 0 { return String(localized: "\(m / 60)h") }
        return String(localized: "\(m / 60)h \(m % 60)m")
    }

    /// « 20:30 », in the wearer's clock format.
    static func clock(_ date: Date) -> String {
        AppClock.hourMinuteFormatter().string(from: date)
    }

    /// « Yesterday », « Today », « Tomorrow », else the short date (« 5 Nov »).
    static func dayWord(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// « Yesterday, 20:30 ».
    static func dayAndClock(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        String(localized: "\(dayWord(date, now: now, calendar: calendar)), \(clock(date))")
    }

    /// « 73 % » from a permille.
    static func percent(permille: Int) -> String {
        String(localized: "\(min(100, max(0, permille / 10)))%")
    }

    /// « 1,25 L » (two decimals, the trailing zero dropped: « 1,5 L », « 2 L »).
    static func litres(ml: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let text = f.string(from: NSNumber(value: max(0, ml) / 1000)) ?? "0"
        return String(localized: "\(text) L")
    }
}
