import SwiftUI
import StrandDesign
import StrandAnalytics

// Personal fork, chantier 15: the words of the six fasting phases (`FastingTimeline.phaseIds`).
//
// Written in the app, so they read without a network or a key; the Coach adds the « for you » part on
// demand (`AICoachEngine.explainFastingPhase`). Indicative landmarks of the general literature, never a
// measurement and never medical advice: every screen that shows them carries the caution line.

enum FastingPhaseText {

    /// The number of phases the texts cover; equals `FastingTimeline.phaseIds.count`.
    static var count: Int { FastingTimeline.phaseIds.count }

    static func name(_ index: Int) -> String {
        switch clamp(index) {
        case 0: return String(localized: "Digestion")
        case 1: return String(localized: "Insulin dropping")
        case 2: return String(localized: "Reserves running low")
        case 3: return String(localized: "Fat burning")
        case 4: return String(localized: "Ketosis")
        default: return String(localized: "Autophagy")
        }
    }

    /// One line under the name in the phases list.
    static func short(_ index: Int) -> String {
        switch clamp(index) {
        case 0: return String(localized: "the meal is being absorbed")
        case 1: return String(localized: "the body draws on its glycogen")
        case 2: return String(localized: "glycogen nearly used up")
        case 3: return String(localized: "fat becomes the fuel")
        case 4: return String(localized: "ketones feed the brain")
        default: return String(localized: "cellular recycling, mostly animal data")
        }
    }

    /// « What is happening ».
    static func what(_ index: Int) -> String {
        switch clamp(index) {
        case 0: return String(localized: "Your body is digesting the last meal. Glucose enters the blood and insulin rises to store it in the liver and the muscles. This is the normal start of every fast.")
        case 1: return String(localized: "The meal is absorbed. Insulin comes down and the liver releases its glycogen to keep blood sugar steady.")
        case 2: return String(localized: "The liver's glycogen is running out. The body gradually switches to fat as its fuel and makes the glucose it lacks from other sources.")
        case 3: return String(localized: "Lipolysis takes over: stored fat is released and burned. The liver starts making ketone bodies, in small amounts.")
        case 4: return String(localized: "Ketone bodies become a major fuel for the brain and the muscles. This is the state 16 to 20 hour fasts aim for.")
        default: return String(localized: "Cellular recycling picks up. Its exact timing in humans is poorly known: the data comes mostly from animal studies. Beyond 24 hours, a doctor's advice is recommended.")
        }
    }

    /// « What you may feel ».
    static func feel(_ index: Int) -> String {
        switch clamp(index) {
        case 0: return String(localized: "Fullness, sometimes a dip in energy after a large meal.")
        case 1: return String(localized: "First waves of hunger, 15 to 20 minutes each. Drinking often sees them off.")
        case 2: return String(localized: "Hunger in waves, steady energy for most people. Coffee or tea without sugar is fine.")
        case 3: return String(localized: "Hunger often eases and focus is good. Sometimes a slightly different breath.")
        case 4: return String(localized: "Mental clarity for many. Keep an eye on water and salt, especially if you train.")
        default: return String(localized: "Tiredness, feeling cold, sensitivity are possible. Stop if you feel dizzy.")
        }
    }

    /// The hours the phase covers, « 4 h to 8 h » or « 24 h and more ».
    static func range(_ index: Int) -> String {
        let i = clamp(index)
        let hours = FastingTimeline.phaseStartHours
        if i + 1 < hours.count {
            return String(localized: "\(hours[i]) h to \(hours[i + 1]) h")
        }
        return String(localized: "\(hours[i]) h and more")
    }

    /// The SF Symbol of the phase.
    static func symbol(_ index: Int) -> String {
        switch clamp(index) {
        case 0: return "fork.knife"
        case 1: return "arrow.down.right"
        case 2: return "battery.25percent"
        case 3: return "flame.fill"
        case 4: return "bolt.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    static func tint(_ index: Int) -> Color {
        let tints = StrandPalette.fastingPhaseTints
        return tints[min(max(clamp(index), 0), tints.count - 1)]
    }

    /// The line every phase readout carries.
    static var caution: String {
        String(localized: "Indicative landmarks: they shift with the last meal, sleep and activity. Not medical advice.")
    }

    /// The words at the end of a row of the phases list for `standing` (`FastingState.phaseStanding`):
    /// « done », « current », « reached at the end », « in 18 min », « not reached ».
    static func standingText(_ standing: FastingPhaseStanding) -> String {
        switch standing {
        case .passed: return String(localized: "done")
        case .current: return String(localized: "current")
        case .reachedAtEnd: return String(localized: "reached at the end")
        case .upcoming(let inMinutes): return String(localized: "in \(FastingFormat.duration(minutes: inMinutes))")
        case .notReached: return String(localized: "not reached")
        }
    }

    private static func clamp(_ index: Int) -> Int { min(max(index, 0), count - 1) }
}
