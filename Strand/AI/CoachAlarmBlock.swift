import Foundation

// Personal fork, chantier 25: the ALARMS block of the Coach's context, so it knows when the wearer will be
// woken and which alarms are on. Built from `WakeSchedule.facts`, the funnel the strap is armed from.

extension CoachFiche {

    static func alarmBlock(_ f: WakeAlarmFacts, zone: TimeZone = .current) -> String {
        func when(_ date: Date) -> String {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = zone
            fmt.dateFormat = "EEE yyyy-MM-dd HH:mm"
            return fmt.string(from: date)
        }
        func alarmClock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60) }
        func days(_ set: Set<Int>) -> String {
            guard !set.isEmpty, set.count < 7 else { return "every day" }
            let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
            return [2, 3, 4, 5, 6, 7, 1].filter(set.contains).compactMap { names[$0] }.joined(separator: " ")
        }
        var lines = ["ALARMS (the Alarms screen; the wake is a buzz of the strap, the phone cannot ring loudly; an "
                     + "adaptive alarm buzzes early when the heart rate rises above the night's trough, a lighter "
                     + "phase, and the deadline is guaranteed):"]
        if f.mainEnabled {
            if f.adaptive {
                lines.append("  main alarm: on, adaptive, earliest \(alarmClock(f.mainMinutes)), window \(f.windowMinutes) min, "
                             + "guaranteed by \(alarmClock(f.mainMinutes + f.windowMinutes)), \(days(f.mainWeekdays))")
            } else {
                lines.append("  main alarm: on, at \(alarmClock(f.mainMinutes)), \(days(f.mainWeekdays))")
            }
        } else {
            lines.append("  main alarm: off")
        }
        if f.fajrEnabled {
            var line = "  Fajr alarm: on, \(f.fajrLeadMinutes) min before the adhan"
                + (f.fajrAdaptive ? ", adaptive in that margin" : "") + ", never after the adhan"
            if let adhan = f.nextAdhan {
                line += "; next adhan \(when(adhan)) ("
                    + (f.adhanFromMosque ? "Masjid At-Tawba timetable from MAWAQIT" : "calculated on the phone, a few minutes early")
                    + ")"
            }
            lines.append(line)
        } else {
            lines.append("  Fajr alarm: off")
        }
        if let next = f.next {
            let kind = next.kind == .fajr ? "Fajr" : "main"
            lines.append(next.adaptive
                         ? "  next wake: \(kind), window \(when(next.start)) to \(when(next.deadline))"
                         : "  next wake: \(kind), \(when(next.deadline))")
        } else if f.mainEnabled || f.fajrEnabled {
            lines.append("  next wake: none planned in the next week")
        }
        if f.mainAnswers > 0 || f.fajrAnswers > 0 {
            lines.append("  learned threshold: main +\(f.mainRiseBpm) bpm (\(f.mainAnswers) answers), "
                         + "Fajr +\(f.fajrRiseBpm) bpm (\(f.fajrAnswers) answers); rises after tired wakes")
        }
        if let last = f.lastWake {
            var line = "  last wake: \(when(last.wokeAt)), "
                + (last.adaptive ? "adaptive buzz" : "at the deadline")
                + (last.kind == .fajr ? " (Fajr)" : "")
            switch last.feeling {
            case .tired?: line += ", felt tired"
            case .fresh?: line += ", felt rested"
            case nil: line += ", not answered"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
