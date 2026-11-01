import Foundation

/// What the user tells the coach about their training (personal fork): goal, rhythm, equipment, pain and
/// anything else. Filled on the "What the coach should know about you" sheet and sent with every question
/// in the coach's context, next to the body profile the app already keeps (`ProfileStore`).
///
/// Stored as JSON in UserDefaults on this device only. Like every other coach setting it is not part of
/// the `.noopbak` whitelist, so the cross-platform backup contract is unchanged; Android has no twin
/// (the coach refonte is iPhone only).
struct CoachProfile: Equatable {

    enum Goal: String, CaseIterable, Identifiable {
        case muscle, strength, fatLoss, fitness
        var id: String { rawValue }

        /// The chip label.
        var label: String {
            switch self {
            case .muscle: return String(localized: "Muscle gain")
            case .strength: return String(localized: "Strength")
            case .fatLoss: return String(localized: "Fat loss")
            case .fitness: return String(localized: "General fitness")
            }
        }

        /// The value as the coach reads it (the context is in English).
        var contextText: String {
            switch self {
            case .muscle: return "muscle gain"
            case .strength: return "strength"
            case .fatLoss: return "fat loss"
            case .fitness: return "general fitness"
            }
        }
    }

    enum Equipment: String, CaseIterable, Identifiable {
        case fullGym, barbellRack, dumbbells, machines, cables, kettlebells, bodyweight
        var id: String { rawValue }

        var label: String {
            switch self {
            case .fullGym: return String(localized: "Full gym")
            case .barbellRack: return String(localized: "Barbell and rack")
            case .dumbbells: return String(localized: "Dumbbells")
            case .machines: return String(localized: "Machines")
            case .cables: return String(localized: "Cables")
            case .kettlebells: return String(localized: "Kettlebells")
            case .bodyweight: return String(localized: "Bodyweight")
            }
        }

        var contextText: String {
            switch self {
            case .fullGym: return "full gym"
            case .barbellRack: return "barbell and rack"
            case .dumbbells: return "dumbbells"
            case .machines: return "machines"
            case .cables: return "cables"
            case .kettlebells: return "kettlebells"
            case .bodyweight: return "bodyweight"
            }
        }
    }

    /// The choices offered on the sheet.
    static let sessionChoices = Array(1...7)
    static let minuteChoices = [30, 45, 60, 75, 90]

    var goal: Goal?
    var sessionsPerWeek: Int?
    var sessionMinutes: Int?
    /// In `Equipment.allCases` order, without duplicates (see `toggled`).
    var equipment: [Equipment] = []
    var equipmentNote = ""
    var constraints = ""
    var other = ""

    var isEmpty: Bool {
        goal == nil && sessionsPerWeek == nil && sessionMinutes == nil && equipment.isEmpty
            && Self.clean(equipmentNote).isEmpty && Self.clean(constraints).isEmpty && Self.clean(other).isEmpty
    }

    /// `equipment` with `item` added or removed, kept in display order.
    func toggled(_ item: Equipment) -> [Equipment] {
        var set = Set(equipment)
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        return Equipment.allCases.filter(set.contains)
    }

    // MARK: Context

    /// The block the coach reads with every question. Says so when nothing is filled, so the coach asks
    /// before prescribing instead of guessing a goal or a pain it was never told about.
    var contextBlock: String {
        let header = "WHAT THE USER TOLD THE COACH (their own answers; respect them):"
        guard !isEmpty else {
            return header + "\n  nothing yet: goal, schedule, equipment and pain are unknown. "
                + "Ask before prescribing when it matters."
        }
        var lines = [header]
        if let goal { lines.append("  goal: " + goal.contextText) }
        switch (sessionsPerWeek, sessionMinutes) {
        case let (n?, m?): lines.append("  training: \(n) sessions per week, about \(m) min each")
        case let (n?, nil): lines.append("  training: \(n) sessions per week")
        case let (nil, m?): lines.append("  training: sessions of about \(m) min")
        case (nil, nil): break
        }
        var kit = equipment.map(\.contextText).joined(separator: ", ")
        let note = Self.clean(equipmentNote)
        if !note.isEmpty { kit = kit.isEmpty ? note : kit + "; " + note }
        if !kit.isEmpty { lines.append("  equipment: " + kit) }
        let pain = Self.clean(constraints)
        if !pain.isEmpty { lines.append("  pain or constraints: " + pain) }
        let rest = Self.clean(other)
        if !rest.isEmpty { lines.append("  other: " + rest) }
        return lines.joined(separator: "\n")
    }

    /// One line for the "What you told the coach" row: "Muscle gain · 3 × 60 min · Full gym".
    var summary: String {
        var parts: [String] = []
        if let goal { parts.append(goal.label) }
        switch (sessionsPerWeek, sessionMinutes) {
        case let (n?, m?): parts.append(String(localized: "\(n) × \(m) min"))
        case let (n?, nil): parts.append(String(localized: "\(n) per week"))
        case let (nil, m?): parts.append(String(localized: "\(m) min"))
        case (nil, nil): break
        }
        if !equipment.isEmpty { parts.append(equipment.map(\.label).joined(separator: ", ")) }
        if parts.isEmpty {
            return isEmpty ? String(localized: "Not filled in yet") : String(localized: "Notes only")
        }
        return parts.joined(separator: " · ")
    }

    /// Free text as sent: trimmed, with line breaks folded so a block stays one line per field.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    // MARK: Storage

    static let storageKey = "ai.coachProfile"

    /// The stored shape: plain strings, so an unknown goal or piece of equipment (written by a later
    /// build) is dropped on its own instead of failing the whole profile.
    private struct Stored: Codable {
        var goal: String?
        var sessionsPerWeek: Int?
        var sessionMinutes: Int?
        var equipment: [String]?
        var equipmentNote: String?
        var constraints: String?
        var other: String?
    }

    static func load(from defaults: UserDefaults = .standard) -> CoachProfile {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return CoachProfile() }
        let kit = Set((stored.equipment ?? []).compactMap(Equipment.init(rawValue:)))
        return CoachProfile(goal: stored.goal.flatMap(Goal.init(rawValue:)),
                            sessionsPerWeek: stored.sessionsPerWeek.flatMap { sessionChoices.contains($0) ? $0 : nil },
                            sessionMinutes: stored.sessionMinutes.flatMap { $0 > 0 ? $0 : nil },
                            equipment: Equipment.allCases.filter(kit.contains),
                            equipmentNote: stored.equipmentNote ?? "",
                            constraints: stored.constraints ?? "",
                            other: stored.other ?? "")
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !isEmpty else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        let stored = Stored(goal: goal?.rawValue, sessionsPerWeek: sessionsPerWeek, sessionMinutes: sessionMinutes,
                            equipment: equipment.map(\.rawValue), equipmentNote: equipmentNote,
                            constraints: constraints, other: other)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.storageKey) }
    }
}
