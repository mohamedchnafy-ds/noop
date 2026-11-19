import Foundation

// Personal fork: the text a dictation writes into a field, the Coach's composer and Nutrition's
// "Dictate a meal". Two pure halves, so StrandTests pins them without a microphone:
//
// - `DictationTranscript` builds one recognition session's spoken text from the recognizer's successive
//   results. Each result revises the utterance being heard, and after a pause the on-device recognizer can
//   start a new utterance whose results carry only the new words. Keeping only the latest result is what
//   made the words said before a pause vanish.
// - `DictationDraft` decides how that spoken text lands in the field: the text already there stays in
//   front, what is said goes after it, and a manual edit made while listening is kept as it was typed.
//
// Neither sends nor adds anything: the screens only write their field, and the user still taps Send or
// "Find the foods". Real repetitions are never removed: there is no deduplication of words, only the
// bookkeeping of which result replaces which.

/// One recognition session's spoken text.
struct DictationTranscript: Equatable {

    /// One result from the recognizer, reduced to what the bookkeeping needs.
    struct Recognition: Equatable {
        /// The whole text of the result (`bestTranscription.formattedString`).
        var text: String
        /// The recognizer marked the end of an utterance (`speechRecognitionMetadata` set on a result that
        /// is not final): the next result may start a new one.
        var utteranceEnded = false
        /// The session's last result.
        var isFinal = false
        /// Start of the result's first word and end of its last word, in seconds from the start of the
        /// audio, when the recognizer reports them (partial results often carry 0, passed as nil).
        var firstWordStart: TimeInterval?
        var lastWordEnd: TimeInterval?

        init(text: String, utteranceEnded: Bool = false, isFinal: Bool = false,
             firstWordStart: TimeInterval? = nil, lastWordEnd: TimeInterval? = nil) {
            self.text = text
            self.utteranceEnded = utteranceEnded
            self.isFinal = isFinal
            self.firstWordStart = firstWordStart
            self.lastWordEnd = lastWordEnd
        }
    }

    /// Utterances heard and closed, oldest first.
    private(set) var closedUtterances: [String] = []
    /// The utterance the recognizer just closed. The next result tells whether the recognizer starts a new
    /// utterance (this one is kept) or carries on a running transcript that already holds it.
    private(set) var justClosed: String?
    private var justClosedEnd: TimeInterval?
    /// The utterance being heard, as last reported.
    private(set) var liveUtterance = ""
    private var liveEnd: TimeInterval?

    init() {}

    /// Everything said in the session so far, in order.
    var spokenText: String {
        joinDictationParts(closedUtterances + [justClosed ?? "", liveUtterance])
    }

    /// Fold one result into the session.
    mutating func ingestRecognition(_ result: Recognition) {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // An empty result never wipes what was heard; it can still close the utterance.
            if result.utteranceEnded || result.isFinal { closeLiveUtterance() }
            return
        }
        if let closed = justClosed {
            justClosed = nil
            if !Self.carriesOn(closed: closed, closedEnd: justClosedEnd, with: text,
                               firstWordStart: result.firstWordStart) {
                closedUtterances.append(closed)
            }
            justClosedEnd = nil
        } else if !liveUtterance.isEmpty,
                  Self.startsNewUtterance(previous: liveUtterance, previousEnd: liveEnd, next: text,
                                          nextStart: result.firstWordStart) {
            closedUtterances.append(liveUtterance)
        }
        liveUtterance = text
        liveEnd = result.lastWordEnd
        if result.utteranceEnded && !result.isFinal { closeLiveUtterance() }
    }

    private mutating func closeLiveUtterance() {
        guard !liveUtterance.isEmpty else { return }
        if let earlier = justClosed { closedUtterances.append(earlier) }
        justClosed = liveUtterance
        justClosedEnd = liveEnd
        liveUtterance = ""
        liveEnd = nil
    }

    /// After an utterance closed: true when the next result is the same running transcript carried on (it
    /// begins with every word of the closed utterance), false when it is a new utterance. A result that
    /// starts after the closed utterance ended is always a new one, even when it repeats it word for word.
    static func carriesOn(closed: String, closedEnd: TimeInterval?, with next: String,
                          firstWordStart: TimeInterval?) -> Bool {
        if let start = firstWordStart, let end = closedEnd, start >= end - timeSlack { return false }
        let closedWords = dictationWords(closed).map(normalizedDictationWord)
        let nextWords = dictationWords(next).map(normalizedDictationWord)
        guard !closedWords.isEmpty, nextWords.count >= closedWords.count else { return false }
        return zip(closedWords, nextWords).allSatisfy { $0 == $1 }
    }

    /// Without an end-of-utterance mark: true when `next` cannot be a revision of `previous` and is the
    /// start of a new utterance. Either it starts after `previous` ended (when both times are known), or it
    /// is shorter and none of its first two words matches the first three of `previous`. Revisions keep
    /// the start of the utterance (« deux cents grammes » → « 200 g » counts as the same start), so this
    /// stays on the side of replacing: a wrong guess here would duplicate words.
    static func startsNewUtterance(previous: String, previousEnd: TimeInterval?, next: String,
                                   nextStart: TimeInterval?) -> Bool {
        if let start = nextStart, let end = previousEnd, start >= end - timeSlack { return true }
        let previousWords = dictationWords(previous).map(normalizedDictationWord)
        let nextWords = dictationWords(next).map(normalizedDictationWord)
        guard !nextWords.isEmpty, nextWords.count < previousWords.count else { return false }
        let head = nextWords.prefix(2)
        let previousHead = previousWords.prefix(3)
        return !head.contains { word in previousHead.contains { sameDictatedWord($0, word) } }
    }

    /// Tolerance on the recognizer's word times.
    static let timeSlack: TimeInterval = 0.05
}

/// How a session's spoken text lands in a field.
struct DictationDraft: Equatable {
    /// The text in front of what is being said: the field as it was when listening started, or as the
    /// user last edited it while listening.
    private(set) var leading: String
    /// How many words of the session's spoken text `leading` already holds (after a manual edit).
    private(set) var absorbedWords = 0
    /// What this draft last wrote into the field.
    private(set) var written: String
    /// Word count of the spoken text behind `written`.
    private var writtenSpokenWords = 0

    init(startingFrom field: String) {
        leading = field
        written = field
    }

    /// The field's new text, given the session's whole spoken text and the field as it stands now. When
    /// the field no longer holds what this draft last wrote, the user edited it: the edit is kept as typed,
    /// and only words heard after it are added.
    mutating func mergeDictation(spoken: String, into field: String) -> String {
        let words = dictationWords(spoken)
        if field != written {
            leading = field
            absorbedWords = writtenSpokenWords
        }
        let fresh = words.dropFirst(min(absorbedWords, words.count)).joined(separator: " ")
        writtenSpokenWords = words.count
        written = appendDictated(fresh, to: leading)
        return written
    }
}

// MARK: - Words

/// The words of a dictated text, split on white space, punctuation left attached.
func dictationWords(_ text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
}

/// A word reduced for comparison: lower case, no accents, letters and digits only.
func normalizedDictationWord(_ word: String) -> String {
    let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    var kept = String.UnicodeScalarView()
    kept.append(contentsOf: folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    return String(kept)
}

/// Two normalized words that a revision may swap for each other: the same word, or two ways of saying
/// a number (the recognizer turns « deux » into « 2 » as the utterance goes on).
func sameDictatedWord(_ a: String, _ b: String) -> Bool {
    a == b || (isDictatedNumber(a) && isDictatedNumber(b))
}

private let dictatedNumberWords: Set<String> = [
    "un", "une", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze", "douze",
    "quinze", "vingt", "trente", "quarante", "cinquante", "soixante", "cent", "cents", "mille", "demi",
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "twelve", "fifteen",
    "twenty", "thirty", "forty", "fifty", "hundred", "thousand", "half",
]

private func isDictatedNumber(_ word: String) -> Bool {
    word.contains(where: \.isNumber) || dictatedNumberWords.contains(word)
}

/// `addition` after `text`, with one space between them unless `text` already ends with white space.
/// `text` is kept exactly as it is.
func appendDictated(_ addition: String, to text: String) -> String {
    guard !addition.isEmpty else { return text }
    guard let last = text.last else { return addition }
    return last.isWhitespace ? text + addition : text + " " + addition
}

private func joinDictationParts(_ parts: [String]) -> String {
    parts.filter { !$0.isEmpty }.joined(separator: " ")
}
