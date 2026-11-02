import Foundation
import WhoopStore

// Personal fork, Nutrition 4d: packaged products, known by their barcode.
//
// The first time a barcode is scanned, Open Food Facts is asked for it (`OpenFoodFacts`, 2 Nov 2026; only
// the barcode is sent, and the setting can turn it off); when it has no usable product, or there is no
// network, the Coach reads the product's nutrition label from a photo (`read_label`). The meal the wearer
// adds keeps the product's values for 100 g on its line, with `foodRef = "ean:<code>"`. The next scan finds
// that line in the journal, on the iPhone, with no request at all. No table of its own.

/// A product the journal already holds: its last line with that barcode.
struct BarcodeProduct: Equatable {
    let barcode: String
    let name: String
    /// Values for 100 g, as read from the label or given by Open Food Facts.
    let per100: MealPer100
    /// The quantity added last time, when it was weighed.
    let lastGrams: Double?
    /// Unix seconds of the meal it was last added with.
    let lastEatenAt: Int
    /// Where the values come from: the journal (on the iPhone) or Open Food Facts (to check before adding).
    var source: Source = .journal

    enum Source: Equatable {
        case journal, openFoodFacts
    }
}

enum BarcodeCatalog {

    /// How far back the journal is searched for a product.
    static let lookbackDays = 1_095

    /// A scanned or typed barcode reduced to its digits; nil unless it has 8 to 14 of them (EAN-8,
    /// UPC-A, EAN-13, GTIN-14).
    static func normalizedBarcode(_ raw: String) -> String? {
        let compact = raw.filter { !$0.isWhitespace }
        guard (8...14).contains(compact.count), compact.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return compact
    }

    /// The reference a journal line keeps for a product ("ean:3017620422003").
    static func productRef(_ barcode: String) -> String { "ean:" + barcode }

    /// The product's latest line among `entries`, nil when none carries its barcode with values for 100 g.
    static func latestProduct(barcode: String, in entries: [MealEntry]) -> BarcodeProduct? {
        let ref = productRef(barcode)
        var best: (item: MealItemRow, per100: MealPer100, eatenAt: Int)?
        for entry in entries {
            for item in entry.items where item.foodRef == ref {
                guard let per100 = item.per100 else { continue }
                if best == nil || entry.meal.eatenAt >= best!.eatenAt {
                    best = (item, per100, entry.meal.eatenAt)
                }
            }
        }
        guard let best else { return nil }
        return BarcodeProduct(barcode: barcode, name: best.item.name, per100: best.per100,
                              lastGrams: best.item.grams, lastEatenAt: best.eatenAt)
    }

    /// The product in the journal of the last `lookbackDays` days, read on the device.
    static func productInJournal(_ store: WhoopStore, barcode: String, now: Date = Date()) async -> BarcodeProduct? {
        let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let entries = (try? await MealJournal.mealJournalRange(
            store, fromDay: MealJournal.mealDayKey(from), toDay: MealJournal.mealDayKey(now))) ?? []
        return latestProduct(barcode: barcode, in: entries)
    }

    /// The quantity offered first: last time's, else 100 g.
    static func startingGrams(_ product: BarcodeProduct) -> Double {
        guard let last = product.lastGrams, last > 0 else { return 100 }
        return MealJournal.clampedPortion(last)
    }

    /// The quick choices under the portion: 100 g, last time's and 200 g, each once, in order.
    static func portionChoices(lastGrams: Double?) -> [Double] {
        var choices: [Double] = [100, 200]
        if let last = lastGrams, last > 0 { choices.append(MealJournal.clampedPortion(last)) }
        return Array(Set(choices)).sorted()
    }

    /// One step of the portion's − / + buttons.
    static let portionStep = 10.0
}

extension MealJournal {
    /// A product's portion kept between 1 g and 2 kg, to one decimal.
    static func clampedPortion(_ grams: Double) -> Double {
        MealMath.tenth(min(max(grams.isFinite ? grams : 100, 1), 2_000))
    }
}
