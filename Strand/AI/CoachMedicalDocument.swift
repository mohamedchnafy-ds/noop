import Foundation
import StrandImport
import WhoopStore

// MARK: - A medical document read by the Coach (personal fork, chantier 23)
//
// A PDF added from the Coach's "+" or the Medical file screen goes whole to Anthropic (the lab-report opt-in)
// in one request outside any conversation, like a lab report. The model files it through
// `record_medical_document`: its kind, a title, the date, a short factual summary, and what it prints of
// results and measurements (Lab Book lines, through `CoachLabReport`), treatments and allergies. The review
// sheet shows each item; nothing is saved before "Save". PURE: the request is `AICoachEngine.readMedicalDocument`.

/// What a document is, as the model files it.
enum MedicalDocumentKind: String, CaseIterable, Codable, Sendable {
    case labReport = "lab_report"
    case prescription
    case consultation
    case imaging
    case measurements
    case other

    var kindTitle: String {
        switch self {
        case .labReport: return String(localized: "Lab report")
        case .prescription: return String(localized: "Prescription")
        case .consultation: return String(localized: "Consultation report")
        case .imaging: return String(localized: "Imaging")
        case .measurements: return String(localized: "Measurements")
        case .other: return String(localized: "Document")
        }
    }

    var symbol: String {
        switch self {
        case .labReport: return "drop"
        case .prescription: return "pills"
        case .consultation: return "stethoscope"
        case .imaging: return "waveform.path.ecg.rectangle"
        case .measurements: return "ruler"
        case .other: return "doc.text"
        }
    }
}

/// A treatment as printed (an ordonnance, a report's current treatment).
struct MedicalTreatment: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    /// "1 g", "10 mg"; empty when not printed.
    var dose: String = ""
    /// "matin et soir", "pendant 7 jours"; empty when not printed.
    var schedule: String = ""
    /// The day it was added from (YYYY-MM-DD), nil when typed.
    var day: String?
    /// The document it came from, nil when typed.
    var documentId: String?

    /// "Doliprane · 1 g · matin et soir".
    var treatmentLine: String { [name, dose, schedule].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// An allergy or intolerance as printed.
struct MedicalAllergy: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var substance: String
    /// "urticaire"; empty when not printed.
    var reaction: String = ""
    var documentId: String?

    var allergyLine: String { reaction.isEmpty ? substance : substance + " · " + reaction }
}

/// One document as the review sheet shows it.
struct CoachMedicalDocument: Equatable {
    var kind: MedicalDocumentKind
    var title: String
    var day: String
    var summary: String
    /// Results and measurements for the Lab Book, nil when it prints none.
    var lab: CoachLabReport?
    var treatments: [Pick<MedicalTreatment>]
    var allergies: [Pick<MedicalAllergy>]

    /// An item with its tick.
    struct Pick<Item: Equatable>: Equatable, Identifiable {
        let id: Int
        var item: Item
        var include: Bool
    }

    static let toolName = "record_medical_document"
    static let maxItems = 40
    /// The summary is cut there, whatever the model writes.
    static let maxSummaryCharacters = 1_200

    // MARK: The tool

    static var definition: [String: Any] {
        let labItems = (((CoachLabReport.definition["input_schema"] as? [String: Any])?["properties"]
            as? [String: Any])?["values"] as? [String: Any])?["items"] as? [String: Any] ?? ["type": "object"]
        let treatment: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The medicine or treatment exactly as printed."],
                "dose": ["type": "string", "description": "The dose as printed (\"1 g\"), empty when none."],
                "schedule": ["type": "string", "description": "When and for how long, as printed, empty when none."],
            ] as [String: Any],
            "required": ["name"],
        ]
        let allergy: [String: Any] = [
            "type": "object",
            "properties": [
                "substance": ["type": "string", "description": "What the user is allergic or intolerant to, as printed."],
                "reaction": ["type": "string", "description": "The reaction as printed, empty when none."],
            ] as [String: Any],
            "required": ["substance"],
        ]
        return [
            "name": toolName,
            "description": "File the user's medical document so the app can show it for review: its kind, a short "
                + "title, its date, a factual summary, and every result, measurement, treatment and allergy it "
                + "prints. Copy values, units, doses and names exactly as printed. Nothing is saved until the "
                + "user reviews each item.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "kind": ["type": "string", "enum": MedicalDocumentKind.allCases.map(\.rawValue)],
                    "title": ["type": "string", "description": "A short title in the user's language (\"Bilan sanguin\", \"Ordonnance Dr Martin\")."],
                    "date": ["type": "string", "description": "YYYY-MM-DD, the day of the exam, sample or visit (else the document's date)."],
                    "summary": ["type": "string", "description": "3 to 6 short factual sentences in the user's language: what was done or found, as the document says it. No diagnosis or opinion of your own."],
                    "values": ["type": "array", "items": labItems, "maxItems": CoachLabReport.maxLines,
                               "description": "Measured results and measurements (blood tests, blood pressure, weight, body composition…)."],
                    "treatments": ["type": "array", "items": treatment, "maxItems": maxItems],
                    "allergies": ["type": "array", "items": allergy, "maxItems": maxItems],
                ] as [String: Any],
                "required": ["kind", "title", "date", "summary"],
            ] as [String: Any],
        ]
    }

    /// The instructions of the one request.
    static func systemPrompt(languageName: String) -> String {
        let catalog = MarkerCatalog.builtIn.map { "\($0.key) (\($0.displayName))" }.joined(separator: ", ")
        return """
        You read one medical document (a PDF the user chose: a lab report, a prescription, a consultation or \
        imaging report, measurements…) and file it for their own medical file. Call \(toolName) once. Write the \
        title and the summary in \(languageName); the summary says, in 3 to 6 short factual sentences, what the \
        document reports, without any diagnosis, opinion or advice of your own. In values, copy every measured \
        result or measurement exactly as printed (value, unit, reference range): never convert, round or \
        interpret. Give marker_key only when the test is one of these: \(catalog). In treatments, copy each \
        medicine with its dose and schedule as printed; in allergies, each allergy or intolerance it states. Leave \
        out names, addresses, identifiers and prices. After the call, say in one short sentence in \
        \(languageName) what you filed. If the document is not medical, say so in one sentence in \
        \(languageName) without calling the tool.
        """
    }

    // MARK: Reading the input

    /// The document from the tool's input; its lab lines are checked against the Lab Book rows of that day.
    static func fromToolInput(_ input: [String: Any], existing: [LabMarkerRow],
                              existingSource: (String) -> String = { $0 }) -> (document: CoachMedicalDocument?, problem: String?) {
        func text(_ key: String, in object: [String: Any] = input) -> String {
            ((object[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let day = text("date")
        guard LabBookFormat.noonEpoch(day) > 0 else { return (nil, "Give the date as YYYY-MM-DD.") }
        let title = text("title")
        guard !title.isEmpty else { return (nil, "Give the document a short title.") }
        let kind = MedicalDocumentKind(rawValue: text("kind")) ?? .other
        let summary = String(text("summary").prefix(maxSummaryCharacters))

        var lab: CoachLabReport?
        if let values = input["values"] as? [[String: Any]], !values.isEmpty {
            lab = CoachLabReport.fromToolInput(["date": day, "values": values], existing: existing,
                                               existingSource: existingSource).report
        }
        var treatments: [Pick<MedicalTreatment>] = []
        for entry in (input["treatments"] as? [[String: Any]] ?? []).prefix(maxItems) {
            let name = text("name", in: entry)
            guard !name.isEmpty else { continue }
            treatments.append(Pick(id: treatments.count,
                                   item: MedicalTreatment(name: name, dose: text("dose", in: entry),
                                                          schedule: text("schedule", in: entry), day: day),
                                   include: true))
        }
        var allergies: [Pick<MedicalAllergy>] = []
        for entry in (input["allergies"] as? [[String: Any]] ?? []).prefix(maxItems) {
            let substance = text("substance", in: entry)
            guard !substance.isEmpty else { continue }
            allergies.append(Pick(id: allergies.count,
                                  item: MedicalAllergy(substance: substance, reaction: text("reaction", in: entry)),
                                  include: true))
        }
        return (CoachMedicalDocument(kind: kind, title: title, day: day, summary: summary, lab: lab,
                                     treatments: treatments, allergies: allergies), nil)
    }
}
