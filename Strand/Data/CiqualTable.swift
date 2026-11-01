import Foundation
import WhoopStore

// Personal fork, Nutrition: the ANSES Ciqual 2025 food composition table, embedded and read on the
// device (`Strand/Resources/Ciqual2025.tsv`, built by `Tools/ciqual_build.py`).
//
// "Anses. 2025. Ciqual French food composition table." Licence Ouverte / Open Licence (Etalab 2.0),
// https://doi.org/10.57745/RDMHWY. Per 100 g: energy as Regulation (EU) 1169/2011 defines it (kcal),
// protein (N × 6.25), carbohydrates and fat; "traces" and "below the quantification limit" count 0, and
// a food missing one of the four is left out of the file.
//
// The Coach looks foods up here (`search_foods`) and logs a meal by Ciqual code (`log_meal`); the app,
// never the model, turns a code and a quantity into calories and macros (`MealJournal.measuredMealLine`).

/// One food of the table.
struct CiqualFood: Equatable, Sendable {
    let code: Int
    let nameFr: String
    let nameEn: String
    /// Values for 100 g.
    let per100: MealPer100

    /// The reference a journal line keeps ("ciqual:9104").
    var foodRef: String { "ciqual:\(code)" }
}

enum CiqualTable {

    /// The citation the licence asks for, shown wherever the values are used.
    static let attribution = "Anses. 2025. Ciqual French food composition table."

    static let resourceName = "Ciqual2025"

    /// Every food of the bundled table, read once.
    static let bundled: [CiqualFood] = readBundledTable()

    private static let bundledIndex: [Int: CiqualFood] =
        Dictionary(bundled.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })

    private static let bundledSearchIndex: [IndexedFood] = bundled.map(IndexedFood.init)

    /// A food of the bundled table by its Ciqual code.
    static func food(code: Int) -> CiqualFood? { bundledIndex[code] }

    static func readBundledTable(bundle: Bundle = .main) -> [CiqualFood] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseCiqualLines(text)
    }

    /// The table's lines: `code \t name_fr \t name_en \t kcal \t protein \t carbs \t fat`, `#` lines skipped.
    static func parseCiqualLines(_ text: String) -> [CiqualFood] {
        var foods: [CiqualFood] = []
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cells.count >= 7, let code = Int(cells[0]),
                  let kcal = Double(cells[3]), let protein = Double(cells[4]),
                  let carbs = Double(cells[5]), let fat = Double(cells[6]) else { continue }
            foods.append(CiqualFood(code: code, nameFr: cells[1], nameEn: cells[2],
                                    per100: MealPer100(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)))
        }
        return foods
    }

    // MARK: Search

    /// A food with its names cut into searchable words.
    struct IndexedFood {
        let food: CiqualFood
        let wordsFr: [String]
        let wordsEn: [String]

        init(_ food: CiqualFood) {
            self.food = food
            wordsFr = CiqualTable.searchWords(food.nameFr)
            wordsEn = CiqualTable.searchWords(food.nameEn)
        }
    }

    /// Words too common to tell foods apart.
    private static let ignoredWords: Set<String> = [
        "de", "du", "des", "la", "le", "les", "au", "aux", "et", "en", "un", "une", "a",
        "the", "of", "and", "with", "in", "or", "ou",
    ]

    /// A name as search words: lower case, without accents, "œ" as "oe", split on anything that is not a
    /// letter or a digit, common words dropped, a final "s" or "x" dropped from words over three letters.
    static func searchWords(_ text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !ignoredWords.contains($0) }
            .map { word in
                word.count > 3 && (word.hasSuffix("s") || word.hasSuffix("x")) ? String(word.dropLast()) : word
            }
    }

    /// The foods that best match `query`, best first.
    ///
    /// Each word of the query scores 3 when a word of the name is that word, 2 when a name word starts
    /// with it (three letters or more); the French and the English names are each scored and the better
    /// one counts. Foods matching every word of the query come first, then the most words matched; ties go
    /// to a match on the name's first word, then to the shorter name, then to the lower code.
    static func search(_ query: String, limit: Int = 8) -> [CiqualFood] {
        rankFoods(query, in: bundledSearchIndex, limit: limit)
    }

    static func rankFoods(_ query: String, in index: [IndexedFood], limit: Int) -> [CiqualFood] {
        let wanted = Array(Set(searchWords(query))).sorted()
        guard !wanted.isEmpty, limit > 0 else { return [] }

        func scoreWords(_ words: [String]) -> (matched: Int, points: Int, firstWord: Bool) {
            var matched = 0
            var points = 0
            for w in wanted {
                if words.contains(w) {
                    matched += 1
                    points += 3
                } else if w.count >= 3, words.contains(where: { $0.hasPrefix(w) }) {
                    matched += 1
                    points += 2
                }
            }
            let firstWord = words.first.map { first in wanted.contains { first == $0 || first.hasPrefix($0) } } ?? false
            return (matched, points, firstWord)
        }

        struct Hit {
            let food: CiqualFood
            let matched: Int
            let points: Int
            let firstWord: Bool
            let length: Int
        }
        var hits: [Hit] = []
        for entry in index {
            let fr = scoreWords(entry.wordsFr)
            let en = scoreWords(entry.wordsEn)
            let best = (fr.matched, fr.points) >= (en.matched, en.points) ? fr : en
            guard best.matched > 0 else { continue }
            let length = best.matched == fr.matched && best.points == fr.points
                ? entry.food.nameFr.count : entry.food.nameEn.count
            hits.append(Hit(food: entry.food, matched: best.matched, points: best.points,
                            firstWord: best.firstWord, length: length))
        }
        hits.sort { a, b in
            if a.matched != b.matched { return a.matched > b.matched }
            if a.points != b.points { return a.points > b.points }
            if a.firstWord != b.firstWord { return a.firstWord }
            if a.length != b.length { return a.length < b.length }
            return a.food.code < b.food.code
        }
        return hits.prefix(limit).map(\.food)
    }
}
