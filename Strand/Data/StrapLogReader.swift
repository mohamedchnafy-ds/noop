import Foundation

// Personal fork (Démarrer tools, 12 Nov.): the strap log in plain words.
//
// The strap log is an engineering log: one line per BLE event, written for whoever triages a bug report. This
// reader turns the lines it recognises into a short sentence the wearer can read, by FIXED rules on the
// line's own text. It never adds a cause or a value the line does not state: a battery REQUEST reads
// « Battery level requested », not a percentage, and a disconnect gives the system's own error text, not a
// guessed reason. A line no rule recognises has no sentence; it stays a technical line, shown only when the
// screen's « Technical lines » switch is on. Copy and Save still export the raw buffer, untouched.
//
// Routine lines that repeat every few seconds (the heart-rate flush, the realtime-HR and battery requests)
// fold into one entry with a counter, so a minute of streaming is three rows, not thirty.

/// What a sentence is about: the screen's filter chips, and the tint of its icon.
enum StrapLogTopic: String, CaseIterable, Equatable {
    case connection, heartRate, history, battery, other, problem
}

/// One recognised line, in words.
struct StrapLogPhrase: Equatable {
    let topic: StrapLogTopic
    let title: String
    let detail: String?
    /// Entries with the same key fold into one while only routine (keyed) entries come between them.
    let foldKey: String?

    init(_ topic: StrapLogTopic, _ title: String, detail: String? = nil, foldKey: String? = nil) {
        self.topic = topic
        self.title = title
        self.detail = detail
        self.foldKey = foldKey
    }
}

/// One row of the plain log: a sentence (possibly folded from several lines) or a run of technical lines.
struct StrapLogEntry: Identifiable, Equatable {
    /// Absolute index, in the log buffer, of the first line folded into this entry.
    let id: Int
    /// "HH:mm" of the newest line folded in (the latest stamped line before it when it has none).
    var clock: String?
    /// "HH:mm" of the first line folded in, for « ×14 since 19:33 ».
    var firstClock: String?
    /// nil = a run of technical lines with no sentence.
    var phrase: StrapLogPhrase?
    /// How many recognised lines this entry stands for (1 = no fold).
    var repeats: Int
    /// The last raw lines folded in, for the « Technical lines » view.
    var rawLines: [String]
    /// How many raw lines this entry stands for in all (technical runs keep only their tail in `rawLines`).
    var lineCount: Int
}

/// The whole reading of a log tail, newest entry first.
struct StrapLogReading: Equatable {
    let entries: [StrapLogEntry]
    /// Lines no rule recognised.
    let technicalLines: Int

    /// The entries the screen shows: the sentences of a topic (all topics for nil), plus the technical runs
    /// when the switch is on.
    func strapLogRows(topic: StrapLogTopic?, technical: Bool) -> [StrapLogEntry] {
        entries.filter { entry in
            guard let phrase = entry.phrase else { return technical && topic == nil }
            return topic == nil || phrase.topic == topic
        }
    }
}

enum StrapLogReader {
    /// Raw lines kept per sentence for the technical view.
    static let rawLinesPerEntry = 6
    /// Raw lines kept per technical run.
    static let rawLinesPerTechnicalRun = 20
    /// How far back a routine line looks for its twin to fold into.
    static let foldLookback = 12

    /// Reads a tail of the strap log. The slice keeps its absolute buffer indices, which become the entry ids.
    static func readStrapLog(_ lines: ArraySlice<String>) -> StrapLogReading {
        var out: [StrapLogEntry] = []
        var technical = 0
        var lastClock: String?
        for index in lines.indices {
            let line = lines[index]
            let (stamp, body) = splitStrapLogClock(line)
            if let stamp { lastClock = stamp }
            guard let phrase = strapLogPhrase(for: body) else {
                technical += 1
                if var last = out.last, last.phrase == nil {
                    last.rawLines.append(line)
                    if last.rawLines.count > rawLinesPerTechnicalRun { last.rawLines.removeFirst() }
                    last.lineCount += 1
                    last.clock = lastClock
                    out[out.count - 1] = last
                } else {
                    out.append(StrapLogEntry(id: index, clock: lastClock, firstClock: lastClock, phrase: nil,
                                             repeats: 1, rawLines: [line], lineCount: 1))
                }
                continue
            }
            if let key = phrase.foldKey, let target = strapLogFoldTarget(out, key: key) {
                var entry = out.remove(at: target)
                // Two technical runs the removed entry separated become one.
                if target > 0, target < out.count, out[target - 1].phrase == nil, out[target].phrase == nil {
                    let next = out.remove(at: target)
                    out[target - 1].rawLines = Array((out[target - 1].rawLines + next.rawLines)
                        .suffix(rawLinesPerTechnicalRun))
                    out[target - 1].lineCount += next.lineCount
                    out[target - 1].clock = next.clock
                }
                entry.phrase = phrase
                entry.repeats += 1
                entry.clock = lastClock
                entry.rawLines = Array((entry.rawLines + [line]).suffix(rawLinesPerEntry))
                entry.lineCount += 1
                out.append(entry)
            } else {
                out.append(StrapLogEntry(id: index, clock: lastClock, firstClock: lastClock, phrase: phrase,
                                         repeats: 1, rawLines: [line], lineCount: 1))
            }
        }
        return StrapLogReading(entries: out.reversed(), technicalLines: technical)
    }

    /// The entry a routine line folds into: the newest entry with its key, looking back over routine and
    /// technical entries only. A sentence without a key (a disconnect, a sync) stops the search, so a fold
    /// never jumps over something that happened.
    static func strapLogFoldTarget(_ entries: [StrapLogEntry], key: String) -> Int? {
        var seen = 0
        var index = entries.count - 1
        while index >= 0, seen < foldLookback {
            if let phrase = entries[index].phrase {
                guard let other = phrase.foldKey else { return nil }
                if other == key { return index }
            }
            seen += 1
            index -= 1
        }
        return nil
    }

    /// "[19:40:39] text" → ("19:40", "text"). A line without a stamp keeps its whole text. A Test Centre
    /// domain tag ("[connection] …") is not a stamp: the line stays as it is, and no rule reads it.
    static func splitStrapLogClock(_ line: String) -> (clock: String?, body: Substring) {
        let chars = Array(line.utf8.prefix(11))
        guard chars.count >= 10, chars[0] == UInt8(ascii: "["), chars[3] == UInt8(ascii: ":"),
              chars[6] == UInt8(ascii: ":"), chars[9] == UInt8(ascii: "]"),
              [1, 2, 4, 5, 7, 8].allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(chars[$0]) })
        else { return (nil, Substring(line)) }
        let start = line.index(line.startIndex, offsetBy: 1)
        let clock = String(line[start..<line.index(start, offsetBy: 5)])
        var body = line.dropFirst(10)
        if body.first == " " { body = body.dropFirst() }
        return (clock, body)
    }

    // MARK: - The rules

    /// The sentence for one line's text (without its stamp), or nil when no rule recognises it.
    static func strapLogPhrase(for body: Substring) -> StrapLogPhrase? {
        let s = body
        // Heart rate saved by the live stream (the « attempt » line is folded into its success, silently).
        if s.hasPrefix("standard-hr transport flush-succeeded") {
            let hr = strapLogInt(s, after: "insertedHRRows=") ?? 0
            let rr = strapLogInt(s, after: "insertedRRRows=") ?? 0
            return StrapLogPhrase(.heartRate, String(localized: "Heart rate saved"),
                                  detail: String(localized: "Heart-rate readings: \(hr) · beat intervals: \(rr)"),
                                  foldKey: "hr.flush")
        }
        if s.hasPrefix("standard-hr transport rebuffered-for-retry") {
            return StrapLogPhrase(.problem, String(localized: "Heart rate not saved yet"),
                                  detail: String(localized: "The readings are kept and will be written again."),
                                  foldKey: "hr.retry")
        }
        if s.hasPrefix("HR: skin contact ") {
            if s.contains("contact supported_detected") {
                return StrapLogPhrase(.heartRate, String(localized: "Skin contact detected"))
            }
            if s.contains("contact supported_not_detected") {
                return StrapLogPhrase(.heartRate, String(localized: "Skin contact lost"))
            }
            return nil
        }
        if s.hasPrefix("HR: "), s.contains("unreadable samples in a row") {
            return StrapLogPhrase(.problem, String(localized: "Heart rate unreadable for a moment"),
                                  detail: String(localized: "Check that the strap sits snug on the wrist."))
        }
        if s.hasPrefix("Realtime HR: arming after bond") {
            return StrapLogPhrase(.heartRate, String(localized: "Live heart rate requested from the strap"))
        }
        if s.hasPrefix("Realtime HR: standard-HR mode") {
            return StrapLogPhrase(.heartRate, String(localized: "Live heart rate in simple mode"),
                                  detail: String(localized: "The radio link is limited: heart rate only."))
        }
        if s.hasPrefix("Continuous HRV: overnight window opened") {
            return StrapLogPhrase(.heartRate, String(localized: "Night HRV: continuous reading started"))
        }
        if s.hasPrefix("Continuous HRV: overnight window closed") {
            return StrapLogPhrase(.heartRate, String(localized: "Night HRV: continuous reading stopped"))
        }

        // Requests the app sends (only the ones worth a sentence; the rest are technical).
        if s.hasPrefix("→ Toggle Realtime HR") {
            if s.contains("payload=00") {
                return StrapLogPhrase(.heartRate, String(localized: "Live heart rate stop requested"),
                                      foldKey: "cmd.realtimeOff")
            }
            return StrapLogPhrase(.heartRate, String(localized: "Live heart rate requested from the strap"),
                                  foldKey: "cmd.realtimeOn")
        }
        if s.hasPrefix("→ Get Battery Level") {
            return StrapLogPhrase(.battery, String(localized: "Battery level requested"), foldKey: "cmd.battery")
        }
        if s.hasPrefix("Command response: ") {
            return strapLogCommandResponse(s.dropFirst("Command response: ".count))
        }

        // Battery values the strap actually reported.
        if s.hasPrefix("[pack] "), let soc = strapLogInt(s, after: "soc=") {
            return StrapLogPhrase(.battery, String(localized: "Battery: \(strapLogPercent(soc))"),
                                  foldKey: "battery.value")
        }
        if s.hasPrefix("HR-strap: battery "), let pct = strapLogInt(s, after: "HR-strap: battery ") {
            return StrapLogPhrase(.battery, String(localized: "Chest strap battery: \(strapLogPercent(pct))"))
        }

        // Connection.
        if s.hasPrefix("Scanning for ") {
            return StrapLogPhrase(.connection, String(localized: "Looking for the strap…"), foldKey: "link.scan")
        }
        if s.hasPrefix("Discovered "), s.hasSuffix("— connecting") {
            return StrapLogPhrase(.connection, String(localized: "Strap found"),
                                  detail: strapLogInt(s, after: "(rssi ").map(strapLogSignal))
        }
        if s.hasPrefix("Connecting to ") {
            return StrapLogPhrase(.connection, String(localized: "Connecting to the strap…"), foldKey: "link.connecting")
        }
        if s.hasPrefix("Connected — discovering services") {
            return StrapLogPhrase(.connection, String(localized: "Connected to the strap"))
        }
        if s.hasPrefix("Already connected to ") {
            return StrapLogPhrase(.connection, String(localized: "Already connected · link refreshed"),
                                  foldKey: "link.refresh")
        }
        if s.hasPrefix("Restored CONNECTED peripheral") {
            return StrapLogPhrase(.connection, String(localized: "Connection picked up again after NOOP restarted"))
        }
        if s.hasPrefix("BONDED") {
            return StrapLogPhrase(.connection, String(localized: "Secure link established"),
                                  detail: String(localized: "Buzz, alarm and history sync are available."))
        }
        if s.hasPrefix("Signal: RSSI "), !s.contains("out of band"), let rssi = strapLogInt(s, after: "Signal: RSSI ") {
            return StrapLogPhrase(.connection, String(localized: "Radio signal checked"),
                                  detail: strapLogSignal(rssi), foldKey: "link.rssi")
        }
        if s.hasPrefix("DIS: firmware=") {
            let rest = s.dropFirst("DIS: firmware=".count)
            let version = rest.prefix { $0 != " " }
            guard !version.isEmpty, version != "?" else { return nil }
            return StrapLogPhrase(.connection, String(localized: "Strap software: \(String(version))"))
        }
        if s.hasPrefix("Disconnected (intentional)") {
            return StrapLogPhrase(.connection, String(localized: "Disconnected by the app"))
        }
        if s.hasPrefix("Disconnected") {
            if s.contains("auto-reconnect paused") {
                return StrapLogPhrase(.problem, String(localized: "Strap disconnected"),
                                      detail: String(localized: "Automatic reconnection is paused: the strap keeps refusing the link."))
            }
            return StrapLogPhrase(.problem, String(localized: "Strap disconnected"), detail: strapLogSystemReason(s))
        }
        if s.hasPrefix("Failed to connect") {
            return StrapLogPhrase(.problem, String(localized: "Could not connect"), detail: strapLogSystemReason(s))
        }
        if s.hasPrefix("No data for >"), let secs = strapLogInt(s, after: "No data for >") {
            return StrapLogPhrase(.problem, String(localized: "Nothing received from the strap for \(secs) s"),
                                  detail: String(localized: "The app restarts the connection."))
        }
        if s.hasPrefix("Bluetooth is off") {
            return StrapLogPhrase(.problem, String(localized: "The phone's Bluetooth is off"),
                                  foldKey: "bt.off")
        }
        if s.hasPrefix("Bluetooth permission not granted") {
            return StrapLogPhrase(.problem, String(localized: "NOOP is not allowed to use Bluetooth"),
                                  detail: String(localized: "iPhone Settings › NOOP › Bluetooth."), foldKey: "bt.denied")
        }

        // History.
        if s.hasPrefix("Backfill: session started") {
            return StrapLogPhrase(.history, String(localized: "Fetching the history…"),
                                  detail: String(localized: "The readings kept on the strap are coming in."))
        }
        if s.hasPrefix("Backfill: session persisted "), let rows = strapLogInt(s, after: "session persisted ") {
            return StrapLogPhrase(.history, String(localized: "History saved"),
                                  detail: String(localized: "Readings saved: \(rows)"))
        }
        if s.hasPrefix("Backfill: completed but the strap banked no sensor history") {
            return StrapLogPhrase(.history, String(localized: "History: nothing new on the strap"))
        }
        if s.hasPrefix("Backfill: session ended") {
            if s.contains("reason=HISTORY_COMPLETE") {
                return StrapLogPhrase(.history, String(localized: "History up to date"),
                                      detail: String(localized: "The strap has sent everything it kept."))
            }
            if s.contains("outcome=nothing-banked") {
                return StrapLogPhrase(.problem, String(localized: "History sync interrupted"),
                                      detail: String(localized: "The strap went quiet. It will retry on the next sync."))
            }
            if s.contains("outcome=drained") {
                return StrapLogPhrase(.history, String(localized: "History fetch finished"))
            }
            return StrapLogPhrase(.history, String(localized: "History fetch stopped"))
        }
        if s.hasPrefix("Sync now: manual sync requested") {
            return StrapLogPhrase(.history, String(localized: "Sync requested"))
        }
        if s.hasPrefix("Sync now: a sync is already in progress") {
            return StrapLogPhrase(.history, String(localized: "A sync is already running"))
        }
        if s.hasPrefix("Sync now: no strap connected") {
            return StrapLogPhrase(.problem, String(localized: "Sync impossible: no strap connected"))
        }
        if s.hasPrefix("Clock correlated:") {
            return StrapLogPhrase(.history, String(localized: "Strap clock checked"), foldKey: "clock.ok")
        }
        if s.hasPrefix("Clock drift detected") {
            return StrapLogPhrase(.history, String(localized: "Strap clock off: setting it to the phone's time"))
        }

        // Alarm, buzz, reminders.
        if s.hasPrefix("Alarm: armed for ") {
            return StrapLogPhrase(.other, String(localized: "Alarm set for \(strapLogUntilDash(s, after: "Alarm: armed for "))"))
        }
        if s.hasPrefix("Alarm: queued for ") {
            return StrapLogPhrase(.other, String(localized: "Alarm waiting (\(strapLogUntilDash(s, after: "Alarm: queued for ")))"),
                                  detail: String(localized: "It is sent at the next connection."))
        }
        if s.hasPrefix("Alarm: strap reports armed for ") {
            let time = s.dropFirst("Alarm: strap reports armed for ".count).prefix { $0 != " " }
            return StrapLogPhrase(.other, String(localized: "The strap confirms the alarm at \(String(time))"))
        }
        if s.hasPrefix("Alarm: strap reports NO alarm") {
            return StrapLogPhrase(.problem, String(localized: "The strap kept no alarm"))
        }
        if s.hasPrefix("Alarm: strap-driven wake fired") {
            return StrapLogPhrase(.other, String(localized: "Strap alarm went off"))
        }
        if s.hasPrefix("Buzz: one-shot fired") {
            return StrapLogPhrase(.other, String(localized: "The strap buzzed"))
        }
        if s.hasPrefix("Inactivity: nudged after a "), let mins = strapLogInt(s, after: "nudged after a ") {
            return StrapLogPhrase(.other, String(localized: "Move reminder after \(mins) min sitting"))
        }

        // Gym session.
        if s.hasPrefix("Lift Log: session paused") {
            return StrapLogPhrase(.other, String(localized: "Session paused"))
        }
        if s.hasPrefix("Lift Log: session resumed") {
            return StrapLogPhrase(.other, String(localized: "Session resumed"))
        }
        if s.hasPrefix("Lift Log: session picked up again") {
            return StrapLogPhrase(.other, String(localized: "Session picked up again after NOOP restarted"))
        }
        if s.hasPrefix("Lift Log: that double-tap was not acted on") {
            return StrapLogPhrase(.other, String(localized: "Strap double-tap ignored"))
        }
        if s == "Moment marked" {
            return StrapLogPhrase(.other, String(localized: "Moment marked"))
        }
        return nil
    }

    /// "TOGGLE_REALTIME_HR(3) → PENDING(2) …" — only non-success replies are logged.
    static func strapLogCommandResponse(_ s: Substring) -> StrapLogPhrase? {
        guard let arrow = s.range(of: " → ") else { return nil }
        let command = s[..<arrow.lowerBound].prefix { $0 != "(" }
        let result = s[arrow.upperBound...].prefix { $0 != "(" && $0 != " " }
        let about: String?
        switch command {
        case "TOGGLE_REALTIME_HR": about = String(localized: "About live heart rate")
        case "GET_BATTERY_LEVEL": about = String(localized: "About the battery")
        default: about = nil
        }
        switch result {
        case "PENDING":
            return StrapLogPhrase(.other, String(localized: "Strap's reply: in progress"), detail: about,
                                  foldKey: "reply.pending.\(command)")
        case "UNSUPPORTED":
            return StrapLogPhrase(.other, String(localized: "Strap's reply: not supported by this strap"), detail: about,
                                  foldKey: "reply.unsupported.\(command)")
        default:
            return nil
        }
    }

    // MARK: - Small readers

    /// The integer right after `marker` (a leading minus sign allowed), or nil.
    static func strapLogInt(_ s: Substring, after marker: String) -> Int? {
        guard let r = s.range(of: marker) else { return nil }
        var rest = s[r.upperBound...]
        var sign = 1
        if rest.first == "-" { sign = -1; rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return sign * value
    }

    /// The text after `marker`, up to " —" (or the end).
    static func strapLogUntilDash(_ s: Substring, after marker: String) -> String {
        let rest = s.dropFirst(marker.count)
        if let dash = rest.range(of: " —") { return String(rest[..<dash.lowerBound]) }
        return String(rest)
    }

    /// The system's own error text in a disconnect line (localised by iOS), without the error token.
    static func strapLogSystemReason(_ s: Substring) -> String? {
        guard let sep = s.range(of: " — ") ?? s.range(of: ": ") else { return nil }
        var reason = s[sep.upperBound...]
        if let token = reason.range(of: " [") { reason = reason[..<token.lowerBound] }
        if let pause = reason.range(of: "; auto-reconnect") { reason = reason[..<pause.lowerBound] }
        let text = reason.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// « Good / fair / weak (−61 dBm) ».
    static func strapLogSignal(_ rssi: Int) -> String {
        let dbm = "\(rssi < 0 ? "−" : "")\(abs(rssi)) dBm"
        if rssi >= -70 { return String(localized: "Signal good (\(dbm))") }
        if rssi >= -85 { return String(localized: "Signal fair (\(dbm))") }
        return String(localized: "Signal weak (\(dbm))")
    }

    /// "73 %" in the locale's style.
    static func strapLogPercent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The one-line state of the strap link above the plain log: one resolver, so any screen that states the
/// link's state in words states it the same way.
struct StrapLinkSummary: Equatable {
    enum Level: Equatable { case good, warning, off }

    let level: Level
    let title: String
    let detail: String?

    /// - Parameters:
    ///   - deviceName: the active device's display name.
    ///   - connected: the radio link is up.
    ///   - trusted: the link is usable (a bonded strap, or a streaming ring).
    ///   - liveHeartRateOnly: a WHOOP streaming HR without the encrypted bond (#69): buzz, alarm and history
    ///     sync do not work on it.
    ///   - liveHeartRate: a live bpm is on screen right now.
    ///   - syncing: the history offload is running.
    ///   - batteryPercent: the ACTIVE device's charge, when it reported one.
    ///   - lastSyncLabel: "2 min ago", already formatted (nil = never synced).
    static func strapLinkSummary(deviceName: String, connected: Bool, trusted: Bool, liveHeartRateOnly: Bool = false,
                                 liveHeartRate: Bool, syncing: Bool, batteryPercent: Int?,
                                 lastSyncLabel: String?) -> StrapLinkSummary {
        var parts: [String] = []
        if liveHeartRate { parts.append(String(localized: "live heart rate arriving")) }
        if syncing {
            parts.append(String(localized: "fetching the history"))
        } else if let lastSyncLabel {
            parts.append(String(localized: "history synced \(lastSyncLabel)"))
        }
        if let batteryPercent { parts.append(String(localized: "battery \(StrapLogReader.strapLogPercent(batteryPercent))")) }
        let detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
        if !connected {
            return StrapLinkSummary(level: .off, title: String(localized: "\(deviceName) not connected"),
                                    detail: lastSyncLabel.map { String(localized: "History synced \($0)") })
        }
        if !trusted {
            return StrapLinkSummary(level: .warning,
                                    title: String(localized: "Connected to \(deviceName), secure link not established"),
                                    detail: detail)
        }
        if liveHeartRateOnly {
            return StrapLinkSummary(level: .warning,
                                    title: String(localized: "Connected to \(deviceName): live heart rate only"),
                                    detail: detail)
        }
        return StrapLinkSummary(level: .good, title: String(localized: "Connected to \(deviceName)"), detail: detail)
    }
}
