import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

// MARK: - Lab markers in Nutrition (personal fork, chantier 8, lot 3)
//
// The latest Lab Book value of the markers Mohamed follows with his diet (vitamin D, ferritin, B12, HbA1c by
// default, plus any he added from a report the Coach read: `NutritionLabMarkers`). Read only: the value is
// printed by `LabBookFormat.readingLabel`, the Lab Book's own label, and a tap opens the Lab Book. No verdict,
// no reference range, nothing changes the nutrition goals.

/// One followed marker: its name, its latest reading as the Lab Book prints it, and the day it was taken.
struct NutritionLabLine: Equatable, Identifiable {
    let key: String
    let name: String
    /// "42 µg/L", "négatif", or "—" when the Lab Book holds no reading yet.
    let reading: String
    /// The day of that reading (local noon of its `yyyy-MM-dd`), nil without one.
    let day: Date?

    var id: String { key }
}

enum NutritionLabLines {

    /// The lines of `keys`, in that order, each with its latest reading among `rows` (greatest `takenAt`,
    /// the reading the Lab Book's card shows).
    static func buildLabLines(keys: [String], rows: [LabMarkerRow]) -> [NutritionLabLine] {
        keys.map { key in
            let latest = rows.filter { $0.markerKey == key }.max { $0.takenAt < $1.takenAt }
            return NutritionLabLine(key: key, name: labMarkerName(key),
                                    reading: LabBookFormat.readingLabel(latest, key: key),
                                    day: latest.flatMap { dayDate($0.day) })
        }
    }

    /// The marker's name in the app's language: the catalog's markers through their `lab: <name>` keys,
    /// a custom one as the Lab Book humanises it.
    static func labMarkerName(_ key: String) -> String {
        guard let definition = MarkerCatalog.definition(for: key) else { return LabBookView.humanise(key) }
        return String(localized: String.LocalizationValue(labKeyPrefix + definition.displayName))
    }

    /// The prefix of the markers' catalogue keys ("lab: Vitamin D"), apart from UI keys spelled the same.
    private static let labKeyPrefix = "lab: "

    private static func dayDate(_ day: String) -> Date? {
        guard let date = dayParser.date(from: day) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: date)
    }

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Every followed marker of the Lab Book, read through the store the Lab Book uses.
    @MainActor
    static func loadLabLines(_ repo: Repository, defaults: UserDefaults = .standard) async -> [NutritionLabLine] {
        let keys = NutritionLabMarkers.storedKeys(defaults)
        guard let store = await repo.storeHandle() else { return buildLabLines(keys: keys, rows: []) }
        var rows: [LabMarkerRow] = []
        for key in keys {
            rows += (try? await store.labMarkers(deviceId: repo.deviceId, markerKey: key)) ?? []
        }
        return buildLabLines(keys: keys, rows: rows)
    }
}

/// The card under the journal: one line per followed marker, then "Open the Lab Book".
struct NutritionLabCard: View {
    let lines: [NutritionLabLine]
    let onOpen: () -> Void

    init(lines: [NutritionLabLine], onOpen: @escaping () -> Void) {
        self.lines = lines
        self.onOpen = onOpen
    }

    private var hasReading: Bool { lines.contains { $0.day != nil } }

    var body: some View {
        Button(action: onOpen) {
            NoopCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.metricRose)
                            .accessibilityHidden(true)
                        Text("Blood markers")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: line.name)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            Text(verbatim: line.reading)
                                .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                                .foregroundStyle(line.day == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                            if let day = line.day {
                                Text(verbatim: NutritionFormat.labReadingDay(day))
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    if hasReading {
                        Text("Your latest Lab Book values, as you noted them. Ask your doctor what they mean.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No value yet: add a reading in the Lab Book, or have the Coach read a lab report.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityHint(Text("Opens the Lab Book"))
    }
}
