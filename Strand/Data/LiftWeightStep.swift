import Foundation

// The weight step of one exercise (fork chantier 18, « palier par exercice »): how far one tap on − or +
// moves the weight on the quick-entry card, and the spacing of its wheel.
//
// A barbell is loaded in 2.5 kg (two 1.25 kg plates), a dumbbell rack goes up by 1 or 2 kg, a machine's
// stack by 5 kg. NOOP has no equipment field, so the first step is GUESSED from the exercise's name, and
// the lifter changes it with one tap on the card; the choice is kept per exercise, on this device.
//
// The step only moves numbers on the card. The progression rule (`LiftProgression`) keeps its own step,
// so the « ↑ 62.5 kg » proposed by the Training screen, the Coach and the session cannot disagree.

enum LiftWeightStep {

    /// The steps the card offers, in the order one tap cycles through them, in kilograms.
    static let choices: [Double] = [1, 2, 2.5, 5]

    /// Where the steps chosen by the lifter are kept: exercise name → kilograms.
    static let defaultsKey = "lift.weightStep.v1"

    static let barbellKg = 2.5
    static let dumbbellKg = 1.0
    static let machineKg = 5.0

    /// The step of `exercise`: the one the lifter chose, else the one its name suggests.
    static func step(for exercise: String, defaults: UserDefaults = .standard) -> Double {
        if let saved = stored(defaults)[exercise], choices.contains(saved) { return saved }
        return guessedStep(for: exercise)
    }

    /// Keep `kg` as the step of `exercise`. A value outside `choices` is ignored.
    static func setStep(_ kg: Double, for exercise: String, defaults: UserDefaults = .standard) {
        guard choices.contains(kg) else { return }
        var all = stored(defaults)
        all[exercise] = kg
        defaults.set(all, forKey: defaultsKey)
    }

    /// The step after `kg` in `choices`, back to the first after the last — the card's « Step » button.
    static func nextStep(after kg: Double) -> Double {
        guard let index = choices.firstIndex(of: kg) else { return choices[0] }
        return choices[(index + 1) % choices.count]
    }

    /// The step an exercise's name suggests: a dumbbell, a machine or a cable, else a barbell. The words
    /// are matched in English and in French, the languages exercise names are written in here, without
    /// case or accents.
    static func guessedStep(for exercise: String) -> Double {
        let name = exercise.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if dumbbellWords.contains(where: { name.contains($0) }) { return dumbbellKg }
        if machineWords.contains(where: { name.contains($0) }) { return machineKg }
        return barbellKg
    }

    private static let dumbbellWords = ["haltere", "dumbbell", "kettlebell"]
    private static let machineWords = ["machine", "poulie", "cable", "pulley", "presse", "leg press",
                                       "pec deck", "butterfly", "pulldown", "tirage", "leg extension",
                                       "leg curl", "smith", "guidee"]

    /// One weight `steps` steps away from `kg` — the card's − and +. Never below zero, and on the step's
    /// grid when it moves, so 61 kg with a 2.5 kg step goes to 62.5, then 65.
    static func moved(_ kg: Double, by steps: Int, step: Double) -> Double {
        guard step > 0, steps != 0 else { return max(0, kg) }
        let position = kg / step
        let onGrid = abs(position - position.rounded()) < 0.0001
        // Off the grid, one step up lands on the grid value just above, one step down on the one just below.
        let start = onGrid ? position.rounded() : (steps > 0 ? position.rounded(.down) : position.rounded(.up))
        let target = (start + Double(steps)) * step
        return max(0, (target * 1000).rounded() / 1000)
    }

    /// The weights the wheel lists for a step: 0 to `maxKg` on the step's grid, with `current` added in its
    /// place when it is off the grid, so opening the wheel never changes the weight by itself.
    static func wheelValues(step: Double, current: Double?, maxKg: Double = 300) -> [Double] {
        guard step > 0 else { return [] }
        let count = Int((maxKg / step).rounded(.down))
        var values = (0...count).map { (Double($0) * step * 1000).rounded() / 1000 }
        if let current, current >= 0, !values.contains(where: { abs($0 - current) < 0.001 }) {
            values.append(current)
            values.sort()
        }
        return values
    }

    private static func stored(_ defaults: UserDefaults) -> [String: Double] {
        (defaults.dictionary(forKey: defaultsKey) as? [String: Double]) ?? [:]
    }
}
