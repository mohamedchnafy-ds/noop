import Foundation

// Supersets in the Lift Log (personal fork).
//
// A SUPERSET is two or more consecutive program lines worked in alternation: one set of each, then the
// rest, then the next round. The grouping is carried by a short label on each line
// (`liftProgramItem.supersetGroup`), and the rule that turns labels into groups lives here, once, so
// the store, the spreadsheet importer, the program editor and the session engine cannot disagree
// about which lines belong together.
//
// THE RULE: consecutive lines with the same label form one superset. A label that appears on a single
// line, or a line whose neighbours carry a different label, is simply done on its own. Contiguity is
// what makes the grouping a property of the ORDER the program already stores — there is no second
// structure that could drift from it.
//
// PURE: no store, no UI. Tested in `LiftSupersetTests`.

public enum LiftSuperset {

    /// Longest label kept. A label is a tag ("A", "B", "Push"), never prose; a pasted sentence in a
    /// spreadsheet cell must not end up stored on every line.
    public static let maxLabelLength = 12

    /// A label as stored: trimmed, upper-cased, nil when blank.
    ///
    /// "A1" / "A2" — the way supersets are usually written on paper — both mean superset "A": a SINGLE
    /// letter followed by digits drops the digits. Anything else is kept whole, so "SS1" and "SS2" stay
    /// two different supersets instead of collapsing into one.
    public static func normalizedLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let chars = Array(trimmed)
        if chars.count >= 2, chars[0].isLetter, chars.dropFirst().allSatisfy(\.isNumber) {
            return String(chars[0])
        }
        return String(trimmed.prefix(maxLabelLength))
    }

    /// Every superset in `labels` (one entry per line, in order), as the range of lines it covers.
    /// Only runs of two or more lines are supersets.
    public static func groups(_ labels: [String?]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = 0
        while start < labels.count {
            var end = start + 1
            if let label = normalizedLabel(labels[start]) {
                while end < labels.count, normalizedLabel(labels[end]) == label { end += 1 }
            }
            if end - start >= 2 { out.append(start..<end) }
            start = end
        }
        return out
    }

    /// The superset line `index` belongs to, or nil when it is done on its own.
    public static func group(of index: Int, in labels: [String?]) -> Range<Int>? {
        groups(labels).first { $0.contains(index) }
    }

    /// The line ranges a session sheet draws as one block each: every superset, and every other line on
    /// its own, in order. Together they cover every line exactly once.
    public static func blocks(_ labels: [String?]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        let supersets = groups(labels)
        while i < labels.count {
            if let g = supersets.first(where: { $0.lowerBound == i }) {
                out.append(g)
                i = g.upperBound
            } else {
                out.append(i..<(i + 1))
                i += 1
            }
        }
        return out
    }

    /// The display letter of the `n`th superset (0-based): A…Z, then AA, AB…
    public static func letter(_ n: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var n = max(0, n)
        var s = ""
        repeat {
            s = String(alphabet[n % 26]) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    /// The labels rewritten canonically: supersets lettered A, B, C… in order, every line on its own
    /// cleared to nil. Grouping is unchanged — only the spelling of the labels is. Written by the editor
    /// and the importer so what is stored always reads the way the session shows it.
    public static func relabeled(_ labels: [String?]) -> [String?] {
        var out = [String?](repeating: nil, count: labels.count)
        for (n, g) in groups(labels).enumerated() {
            for i in g { out[i] = letter(n) }
        }
        return out
    }

    /// "A1", "A2"… — the letter of the line's superset and its position in it, or nil for a line done
    /// on its own. The letter is the superset's position among the program's supersets, so it reads
    /// the same however the labels happen to be spelled.
    public static func tag(of index: Int, in labels: [String?]) -> String? {
        let all = groups(labels)
        guard let n = all.firstIndex(where: { $0.contains(index) }) else { return nil }
        return letter(n) + String(index - all[n].lowerBound + 1)
    }

    /// The letter of the superset line `index` belongs to ("A"), or nil.
    public static func groupLetter(of index: Int, in labels: [String?]) -> String? {
        groups(labels).firstIndex(where: { $0.contains(index) }).map(letter)
    }
}
