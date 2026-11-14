import Foundation
import WhoopStore

// Fork chantier 21: the movements the execution figure knows, what each one says, and how an exercise
// finds its movement.
//
// NOOP ships no exercise catalogue: an exercise is the name the user typed. So a movement is found in
// two steps, through ONE resolver (`LiftMovementChoice.resolveMovement`): the user's own choice for
// that exact name if there is one, else a match on the words of the name, in French and English
// (`LiftMovement.recognize`). A name nothing matches has no figure until the user picks a movement.
//
// The choice is kept on the device (UserDefaults), by exercise name. It is not in the `.noopbak`: it is
// a display preference, and losing it only brings back the match on the name.

enum LiftMovement: String, CaseIterable, Identifiable {
    case squat, deadlift, romanianDeadlift, benchPress, inclinePress, overheadPress, row, latPulldown
    case pullUp, dips, pushUp, curl, tricepsPushdown, lunge, hipThrust, lateralRaise, legExtension
    case legCurl, calfRaise, crunch, plank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .squat: return String(localized: "Squat")
        case .deadlift: return String(localized: "Deadlift")
        case .romanianDeadlift: return String(localized: "Romanian deadlift")
        case .benchPress: return String(localized: "Bench press")
        case .inclinePress: return String(localized: "Incline press")
        case .overheadPress: return String(localized: "Overhead press")
        case .row: return String(localized: "Bent-over row")
        case .latPulldown: return String(localized: "Lat pulldown")
        case .pullUp: return String(localized: "Pull-up")
        case .dips: return String(localized: "Dips")
        case .pushUp: return String(localized: "Push-up")
        case .curl: return String(localized: "Biceps curl")
        case .tricepsPushdown: return String(localized: "Triceps pushdown")
        case .lunge: return String(localized: "Lunge")
        case .hipThrust: return String(localized: "Hip thrust")
        case .lateralRaise: return String(localized: "Lateral raise")
        case .legExtension: return String(localized: "Leg extension")
        case .legCurl: return String(localized: "Leg curl")
        case .calfRaise: return String(localized: "Calf raise")
        case .crunch: return String(localized: "Crunch")
        case .plank: return String(localized: "Plank")
        }
    }

    /// The muscles the movement works, the main one first: drawn in the highlight colour on the figure.
    var muscles: (primary: LiftMuscle, secondaries: [LiftMuscle]) {
        switch self {
        case .squat: return (.quads, [.glutes, .adductors])
        case .deadlift: return (.glutes, [.hamstrings, .lowerBack])
        case .romanianDeadlift: return (.hamstrings, [.glutes, .lowerBack])
        case .benchPress, .inclinePress: return (.chest, [.frontDelts, .triceps])
        case .overheadPress: return (.frontDelts, [.sideDelts, .triceps])
        case .row: return (.upperBack, [.lats, .biceps])
        case .latPulldown, .pullUp: return (.lats, [.biceps, .upperBack])
        case .dips, .pushUp: return (.chest, [.triceps, .frontDelts])
        case .curl: return (.biceps, [.forearms])
        case .tricepsPushdown: return (.triceps, [])
        case .lunge: return (.quads, [.glutes])
        case .hipThrust: return (.glutes, [.hamstrings])
        case .lateralRaise: return (.sideDelts, [])
        case .legExtension: return (.quads, [])
        case .legCurl: return (.hamstrings, [])
        case .calfRaise: return (.calves, [])
        case .crunch: return (.abs, [])
        case .plank: return (.abs, [.obliques])
        }
    }

    /// Three cues of good form, in the order they matter: set-up, the movement, the finish.
    var cues: [String] {
        switch self {
        case .squat: return [
            String(localized: "Feet shoulder-width apart, toes slightly out."),
            String(localized: "Knees track over the toes, heels stay down."),
            String(localized: "Sit down to thighs parallel, back straight, chest up.")]
        case .deadlift: return [
            String(localized: "Bar over the middle of the foot, shins close to it."),
            String(localized: "Back flat, push the floor away with your legs."),
            String(localized: "Hips and shoulders rise together, stand tall at the top.")]
        case .romanianDeadlift: return [
            String(localized: "Knees slightly bent, and they stay that way."),
            String(localized: "Push the hips back, the bar sliding along the thighs."),
            String(localized: "Stop when the hamstrings stretch, back flat.")]
        case .benchPress: return [
            String(localized: "Shoulder blades squeezed, feet flat on the floor."),
            String(localized: "Lower the bar to the lower chest, elbows at about 45°."),
            String(localized: "Press up and slightly back, hips stay on the bench.")]
        case .inclinePress: return [
            String(localized: "Bench at 30 to 45°, shoulder blades squeezed."),
            String(localized: "Lower the bar to the upper chest."),
            String(localized: "Press straight up over the shoulders.")]
        case .overheadPress: return [
            String(localized: "Glutes and abs tight, no arching."),
            String(localized: "Press the bar straight up, moving the head out of its way."),
            String(localized: "Lock out overhead, the bar above the middle of the foot.")]
        case .row: return [
            String(localized: "Torso tilted forward, back flat, knees soft."),
            String(localized: "Pull the bar to the navel, elbows close to the body."),
            String(localized: "Squeeze the shoulder blades at the top, lower under control.")]
        case .latPulldown: return [
            String(localized: "Thighs locked under the pads, chest up."),
            String(localized: "Pull the bar to the upper chest, elbows down and back."),
            String(localized: "Let the bar rise slowly to straight arms.")]
        case .pullUp: return [
            String(localized: "Hang with straight arms, shoulders active."),
            String(localized: "Pull the chest toward the bar, without swinging."),
            String(localized: "Lower all the way down under control.")]
        case .dips: return [
            String(localized: "Shoulders down, away from the ears."),
            String(localized: "Lower until the upper arms are parallel to the floor."),
            String(localized: "Push back up to straight arms.")]
        case .pushUp: return [
            String(localized: "Hands under the shoulders, body in one straight line."),
            String(localized: "Lower the chest close to the floor, elbows at about 45°."),
            String(localized: "Push back up without letting the hips sag.")]
        case .curl: return [
            String(localized: "Elbows pinned to your sides: they don't move."),
            String(localized: "Curl up without swinging the torso."),
            String(localized: "Lower slowly to straight arms.")]
        case .tricepsPushdown: return [
            String(localized: "Elbows tucked at your sides, and they stay still."),
            String(localized: "Push down until the arms are straight."),
            String(localized: "Come back up slowly to chest height.")]
        case .lunge: return [
            String(localized: "A long step, torso upright."),
            String(localized: "Lower the back knee toward the floor."),
            String(localized: "Push up through the front heel, front knee over the foot.")]
        case .hipThrust: return [
            String(localized: "Upper back on the bench, feet flat on the floor."),
            String(localized: "Drive the hips up by squeezing the glutes."),
            String(localized: "Chin tucked, ribs down: no arching at the top.")]
        case .lateralRaise: return [
            String(localized: "Elbows slightly bent, torso still."),
            String(localized: "Raise the arms out to the side, up to shoulder height."),
            String(localized: "Lower slowly, without swinging.")]
        case .legExtension: return [
            String(localized: "Back against the pad, knees in line with the machine's pivot."),
            String(localized: "Straighten the legs fully and squeeze the thighs."),
            String(localized: "Lower slowly, without letting the weight drop.")]
        case .legCurl: return [
            String(localized: "Hips pressed into the pad."),
            String(localized: "Curl the heels toward the glutes."),
            String(localized: "Return slowly to straight legs.")]
        case .calfRaise: return [
            String(localized: "Balls of the feet on the edge, legs straight."),
            String(localized: "Rise as high as you can onto the toes."),
            String(localized: "Lower slowly until the heels stretch.")]
        case .crunch: return [
            String(localized: "Lower back pressed into the floor."),
            String(localized: "Curl the shoulders up by squeezing the abs."),
            String(localized: "Lower slowly, without pulling on the neck.")]
        case .plank: return [
            String(localized: "Elbows under the shoulders."),
            String(localized: "Body in one straight line from head to heels."),
            String(localized: "Squeeze the glutes and abs, and keep breathing.")]
        }
    }

    /// How the figure draws and times this movement (`LiftFigure.swift`). Poses tuned on a rendered
    /// contact sheet, frame by frame, before they were written here.
    var figure: LiftFigureSpec {
        typealias P = LiftPose
        switch self {
        case .squat:
            return LiftFigureSpec(anchor: .ankle, arm: .reach(base: .shoulder, torsoFrame: true, bend: -1),
                                  prop: .plate, highlights: [.thigh, .hip],
                                  start: P(torso: 4, hx: -6, hy: -1),
                                  end: P(shin: 30, thigh: -85, torso: 40, hx: -6, hy: -1))
        case .deadlift:
            return LiftFigureSpec(anchor: .ankle, prop: .plate, highlights: [.thigh, .hip, .lowerTorso],
                                  start: P(shin: 25, thigh: -80, torso: 62, ua: 188, fa: 188),
                                  end: P(ua: 182, fa: 182),
                                  first: (.lifting, 1), second: (.lowering, 2))
        case .romanianDeadlift:
            return LiftFigureSpec(anchor: .ankle, prop: .plate, highlights: [.thigh, .hip, .lowerTorso],
                                  start: P(shin: 3, thigh: -4, torso: 2, ua: 182, fa: 182),
                                  end: P(shin: 10, thigh: -14, torso: 78, ua: 192, fa: 192))
        case .benchPress:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .shoulder, torsoFrame: false, bend: 1),
                                  prop: .plate, bench: .flat, highlights: [.upperArm, .upperTorso],
                                  start: P(shin: -10, thigh: -70, torso: -90, hy: -61),
                                  end: P(shin: -10, thigh: -70, torso: -90, hx: 12, hy: -8),
                                  second: (.pushing, 1))
        case .inclinePress:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .shoulder, torsoFrame: false, bend: 1),
                                  prop: .plate, bench: .incline, highlights: [.upperArm, .upperTorso],
                                  start: P(shin: -8, thigh: -85, torso: -58, hx: 6, hy: -60),
                                  end: P(shin: -8, thigh: -85, torso: -58, hx: 15, hy: -4),
                                  second: (.pushing, 1))
        case .overheadPress:
            return LiftFigureSpec(anchor: .ankle, arm: .reach(base: .shoulder, torsoFrame: false, bend: -1),
                                  prop: .plate, highlights: [.shoulders, .upperArm],
                                  start: P(torso: -2, hx: 9, hy: -3),
                                  end: P(torso: -4, hx: 2, hy: -61),
                                  first: (.pushing, 1), second: (.lowering, 2))
        case .row:
            return LiftFigureSpec(anchor: .ankle, arm: .reach(base: .shoulder, torsoFrame: false, bend: 1),
                                  prop: .plate, highlights: [.upperArm, .upperTorso],
                                  start: P(shin: 18, thigh: -50, torso: 55, hx: -10.9, hy: 61),
                                  end: P(shin: 18, thigh: -50, torso: 55, hx: -25.9, hy: 29.9),
                                  first: (.pulling, 1), second: (.lowering, 2))
        case .latPulldown:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .shoulder, torsoFrame: false, bend: 1),
                                  prop: .handle, cable: true, bench: .seat, highlights: [.upperArm, .upperTorso],
                                  start: P(thigh: -90, torso: -10, hx: 6, hy: -61),
                                  end: P(thigh: -90, torso: -18, hx: 14, hy: 4),
                                  first: (.pulling, 1), second: (.returning, 2))
        case .pullUp:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .world, torsoFrame: false, bend: 1),
                                  prop: .bar, ground: .none, highlights: [.upperArm, .upperTorso],
                                  start: P(shin: 35, thigh: -12, torso: 2, hx: 6, hy: -119.5),
                                  end: P(ay: -46, shin: 30, thigh: -25, torso: -6, hx: 6, hy: -119.5),
                                  first: (.pulling, 1), second: (.lowering, 2))
        case .dips:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .world, torsoFrame: false, bend: -1),
                                  prop: .bar, ground: .none, highlights: [.upperArm, .upperTorso],
                                  start: P(shin: 40, thigh: -14, torso: 8, hx: 9, hy: 3),
                                  end: P(ax: -6, ay: 28, shin: 38, thigh: -30, torso: 22, hx: 9, hy: 3),
                                  second: (.pushing, 1))
        case .pushUp:
            return LiftFigureSpec(anchor: .ankle, arm: .reach(base: .world, torsoFrame: false, bend: -1),
                                  ground: .at(4), highlights: [.upperArm, .upperTorso],
                                  start: P(ay: -9, shin: 70, thigh: 70, torso: 70, foot: 150, neck: 6, hx: 142.8),
                                  end: P(ay: -9, shin: 80, thigh: 80, torso: 80, foot: 155, neck: 6, hx: 142.8),
                                  second: (.pushing, 1))
        case .curl:
            return LiftFigureSpec(anchor: .ankle, prop: .dumbbell, highlights: [.upperArm],
                                  start: P(ua: 178, fa: 178),
                                  end: P(ua: 176, fa: 22),
                                  first: (.curling, 1), second: (.lowering, 2))
        case .tricepsPushdown:
            return LiftFigureSpec(anchor: .ankle, prop: .handle, cable: true, highlights: [.upperArm],
                                  start: P(shin: 4, thigh: -4, torso: 10, ua: 176, fa: 58),
                                  end: P(shin: 4, thigh: -4, torso: 10, ua: 176, fa: 176),
                                  first: (.pushing, 1), second: (.returning, 2))
        case .lunge:
            return LiftFigureSpec(anchor: .ankle, farLeg: .reach(bend: -1), prop: .dumbbell,
                                  highlights: [.thigh, .hip],
                                  start: P(shin: 4, thigh: -25, foot2: 118, a2x: -62, a2y: -9, ua: 182, fa: 182),
                                  end: P(shin: 20, thigh: -80, torso: 6, foot2: 118, a2x: -62, a2y: -9,
                                         ua: 184, fa: 184))
        case .hipThrust:
            return LiftFigureSpec(anchor: .ankle, arm: .reach(base: .hip, torsoFrame: false, bend: 1),
                                  prop: .plateOnHip, bench: .thrust, highlights: [.hip, .thigh],
                                  start: P(shin: -15, thigh: -110, torso: -76, neck: -25, hx: 2, hy: -12),
                                  end: P(shin: -5, thigh: -90, torso: -95, neck: -35, hx: 2, hy: -12),
                                  first: (.lifting, 1), second: (.lowering, 2))
        case .lateralRaise:
            return LiftFigureSpec(anchor: .hip, hipHalfWidth: 7, shoulderHalfWidth: 13, mirrorsFarArm: true,
                                  prop: .dumbbellPair, highlights: [.shoulders],
                                  start: P(shin: 2, thigh: 4, foot: 270, shin2: -2, thigh2: -4, foot2: 90,
                                           ua: 188, fa: 186),
                                  end: P(shin: 2, thigh: 4, foot: 270, shin2: -2, thigh2: -4, foot2: 90,
                                         ua: 262, fa: 258),
                                  first: (.raising, 1), second: (.lowering, 2))
        case .legExtension:
            return LiftFigureSpec(anchor: .hip, pad: true, bench: .seat, ground: .at(52), highlights: [.thigh],
                                  start: P(thigh: -90, torso: -4, ua: 186, fa: 160),
                                  end: P(shin: -88, thigh: -90, torso: -4, foot: 2, ua: 186, fa: 160),
                                  first: (.raising, 1), second: (.lowering, 2))
        case .legCurl:
            return LiftFigureSpec(anchor: .hip, pad: true, bench: .prone, ground: .at(46), highlights: [.thigh],
                                  start: P(shin: -90, thigh: -90, torso: -90, foot: 180, neck: 8, ua: 200, fa: 225),
                                  end: P(shin: -172, thigh: -90, torso: -90, neck: 8, ua: 200, fa: 225),
                                  first: (.curling, 1), second: (.lowering, 2))
        case .calfRaise:
            return LiftFigureSpec(anchor: .ankle, prop: .dumbbell, ground: .at(4), highlights: [.shin],
                                  start: P(),
                                  end: P(ax: 2.7, ay: -8.6, foot: 125),
                                  first: (.raising, 1), second: (.lowering, 2))
        case .crunch:
            return LiftFigureSpec(anchor: .hip, arm: .reach(base: .shoulder, torsoFrame: true, bend: 1),
                                  ground: .at(6), highlights: [.lowerTorso],
                                  start: P(shin: -32, thigh: -140, torso: -90, neck: -5, hx: 9, hy: 12),
                                  end: P(shin: -32, thigh: -140, torso: -58, neck: 15, hx: 9, hy: 12),
                                  first: (.raising, 1), second: (.lowering, 2))
        case .plank:
            return LiftFigureSpec(anchor: .ankle, ground: .at(4), highlights: [.lowerTorso],
                                  start: P(ay: -8, shin: 79, thigh: 79, torso: 79, foot: 150, neck: 4, fa: 90),
                                  end: nil)
        }
    }

    /// "Lowering 2 s · Lifting 1 s"; a hold says what to hold.
    var tempoLine: String {
        let spec = figure
        guard spec.end != nil else { return String(localized: "Hold, body in one line") }
        return [spec.first, spec.second]
            .map { String(localized: "\($0.phase.label) \($0.seconds) s") }
            .joined(separator: " · ")
    }

    // MARK: - Recognising a movement from an exercise's name

    /// Names that look like a known movement but are another one: no figure rather than a wrong one.
    /// Each entry is a set of word starts that must all appear.
    static let notAMovement: [[String]] = [
        ["leg press"], ["presse", "cuisse"], ["presse", "jambe"], ["ecarte"], ["fly"], ["pec deck"],
        ["oiseau"], ["face pull"], ["shrug"], ["haussement"], ["lombaire"], ["hyperextension"],
        ["back extension"]
    ]

    /// The word starts each movement is recognised by, in the order they are tried: the specific before
    /// the generic ("Curl ischio" is a leg curl before it is a curl, "Squat bulgare" a lunge).
    static let recognisedBy: [(LiftMovement, [[String]])] = [
        (.romanianDeadlift, [["souleve de terre roumain"], ["sdt roumain"], ["roumain"], ["romanian"], ["rdl"],
                             ["jambes tendues"], ["stiff leg"]]),
        (.deadlift, [["souleve de terre"], ["deadlift"], ["sdt"], ["souleve"]]),
        (.hipThrust, [["hip thrust"], ["pont fessier"], ["glute bridge"], ["releve de bassin"], ["releve du bassin"]]),
        (.lunge, [["fente"], ["lunge"], ["split squat"], ["bulgare"], ["bulgarian"]]),
        (.legExtension, [["leg extension"], ["leg ext"], ["extension", "jambe"], ["extension", "quadri"]]),
        (.legCurl, [["leg curl"], ["curl", "ischio"], ["curl", "jambe"], ["ischio"], ["hamstring curl"]]),
        (.calfRaise, [["mollet"], ["calf"]]),
        (.inclinePress, [["developpe", "incline"], ["incline press"], ["incline bench"]]),
        (.benchPress, [["developpe", "couche"], ["developpe", "decline"], ["bench"], ["chest press"]]),
        (.overheadPress, [["developpe", "militaire"], ["militaire"], ["overhead"], ["ohp"], ["developpe", "epaule"],
                          ["developpe", "nuque"], ["shoulder press"], ["arnold"], ["push press"]]),
        (.lateralRaise, [["elevation", "lateral"], ["lateral raise"], ["side raise"]]),
        (.latPulldown, [["tirage", "vertical"], ["tirage", "poitrine"], ["tirage", "nuque"], ["tirage", "haut"],
                        ["pulldown"], ["pull down"], ["lat pull"]]),
        (.pullUp, [["traction"], ["pull up"], ["pullup"], ["chin up"], ["chinup"]]),
        (.row, [["rowing"], ["row"], ["tirage"], ["t bar"]]),
        (.dips, [["dip"]]),
        (.pushUp, [["pompe"], ["push up"], ["pushup"]]),
        (.tricepsPushdown, [["triceps"], ["pushdown"], ["push down"], ["barre au front"], ["skull"], ["kickback"],
                            ["extension"]]),
        (.curl, [["curl"], ["biceps"], ["marteau"], ["hammer"]]),
        (.squat, [["squat"], ["goblet"], ["hack"]]),
        (.crunch, [["crunch"], ["abdo"], ["sit up"], ["releve de buste"], ["enroule"]]),
        (.plank, [["gainage"], ["planche"], ["plank"]])
    ]

    /// The name lower-cased, accents folded, every run of other characters one space, with a space in
    /// front so a word start is " word".
    static func foldedExerciseName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .lowercased()
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return " " + words.joined(separator: " ")
    }

    /// The movement an exercise's name reads as, or nil.
    static func recognize(exerciseName: String) -> LiftMovement? {
        let text = foldedExerciseName(exerciseName)
        func nameHas(_ group: [String]) -> Bool { group.allSatisfy { text.contains(" " + $0) } }
        if notAMovement.contains(where: nameHas) { return nil }
        return recognisedBy.first { $0.1.contains(where: nameHas) }?.0
    }
}

extension LiftFigurePhase {
    var label: String {
        switch self {
        case .ready: return String(localized: "Ready")
        case .lowering: return String(localized: "Lowering")
        case .lifting: return String(localized: "Rising")
        case .pushing: return String(localized: "Pushing")
        case .pulling: return String(localized: "Pulling")
        case .raising: return String(localized: "Raising")
        case .curling: return String(localized: "Curling")
        case .returning: return String(localized: "Returning")
        case .pausing: return String(localized: "Pause")
        case .holding: return String(localized: "Holding")
        }
    }
}

/// The user's own movement for an exercise, kept on the device by exercise name.
enum LiftMovementChoice {
    /// The `@AppStorage` key: a JSON object, exercise name → movement raw value.
    static let storageKey = "lift.movementChoice.v1"

    static func decodeChoices(_ raw: String) -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func encodeChoices(_ map: [String: String]) -> String {
        guard !map.isEmpty, let data = try? JSONEncoder().encode(map) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// THE resolver: the user's choice for this name, else the movement its words read as. Every
    /// reader of an exercise's movement (the card's tile, the sheet) goes through it.
    static func resolveMovement(exercise: String, choices raw: String) -> (movement: LiftMovement?, chosen: Bool) {
        if let picked = decodeChoices(raw)[exercise], let movement = LiftMovement(rawValue: picked) {
            return (movement, true)
        }
        return (LiftMovement.recognize(exerciseName: exercise), false)
    }

    /// The stored choices once `movement` is picked for `exercise`. Picking what the name already reads
    /// as removes the entry, so a later better match on the name is not hidden by a stale copy.
    static func choosingMovement(_ movement: LiftMovement, for exercise: String, in raw: String) -> String {
        var map = decodeChoices(raw)
        if LiftMovement.recognize(exerciseName: exercise) == movement {
            map.removeValue(forKey: exercise)
        } else {
            map[exercise] = movement.rawValue
        }
        return encodeChoices(map)
    }
}
