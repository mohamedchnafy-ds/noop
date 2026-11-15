import Foundation
import StrandImport
import WhoopStore

// MARK: - A medical document read by the Coach (personal fork, chantier 23)
//
// The request behind "PDF document" in the Coach's "+" and "Add a PDF document" in the Medical file: one
// request outside any conversation, under the lab-report opt-in (the PDF goes whole to Anthropic), the same
// size limits, and `record_medical_document`. "Save" in the review sheet writes the Lab Book lines (through
// `saveLabReport`), the document with its PDF, and the ticked treatments and allergies (`MedicalFileStore`).

/// How reading a document ended.
enum MedicalDocumentOutcome: Equatable {
    case document(CoachMedicalDocument)
    /// The model filed nothing: its own sentence (not a medical document, nothing readable).
    case nothing(String)
    /// It could not run (opt-in off, key, size, network): a message to show.
    case failure(String)
}

extension AICoachEngine {

    /// Read the medical document `pdf`, its lab lines checked against the Lab Book rows already stored.
    func readMedicalDocument(pdf: Data) async -> MedicalDocumentOutcome {
        guard labReportConsent else {
            return .failure(String(localized: "Turn on “Lab reports (PDF)” in What the coach reads first."))
        }
        guard canEstimateMeals, let key = resolvedKey else {
            return .failure(AICoachError.noKey.errorDescription ?? "")
        }
        if let problem = Self.labReportSizeProblem(pdf) { return .failure(problem) }
        var existing: [LabMarkerRow] = []
        if let store = await repo.storeHandle() {
            for category in LabMarkerCategory.allCases {
                let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
                existing.append(contentsOf: rows)
            }
        }
        let user: [String: Any] = [
            "role": "user",
            "content": [
                ["type": "document",
                 "source": ["type": "base64", "media_type": "application/pdf",
                            "data": pdf.base64EncodedString()] as [String: Any]] as [String: Any],
                ["type": "text", "text": "File this medical document."] as [String: Any],
            ],
        ]
        var conversation: [[String: Any]] = [user]
        let system = CoachMedicalDocument.systemPrompt(languageName: Self.mealEstimateLanguageName())
        var lastText = ""
        do {
            for round in 0...Self.labReportRounds {
                let allowTools = round < Self.labReportRounds
                let body = try AnthropicToolRequest.body(model: model, system: system, messages: conversation,
                                                         tools: [CoachMedicalDocument.definition],
                                                         allowTools: allowTools, maxTokens: 16_000)
                let turn = try await streamToolRound(key: key, body: body) { _ in }
                lastText = turn.text
                guard allowTools, turn.stopReason == "tool_use", !turn.toolCalls.isEmpty else { break }
                var results: [(id: String, text: String, isError: Bool)] = []
                for call in turn.toolCalls {
                    guard call.name == CoachMedicalDocument.toolName else {
                        results.append((call.id, "Unknown tool \(call.name).", true))
                        continue
                    }
                    let parsed = CoachMedicalDocument.fromToolInput(CoachTools.input(fromJSON: call.inputJSON),
                                                                    existing: existing,
                                                                    existingSource: Self.labSourceName)
                    if let document = parsed.document { return .document(document) }
                    results.append((call.id, parsed.problem ?? "Nothing usable.", true))
                }
                try Task.checkCancellation()
                conversation.append(AnthropicToolRequest.assistant(turn))
                conversation.append(AnthropicToolRequest.toolResults(results))
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure("") }
            return .failure((error as? AICoachError)?.errorDescription ?? error.localizedDescription)
        }
        let said = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        return .nothing(said.isEmpty ? String(localized: "Nothing was found to file in that document.") : said)
    }

    /// "Save": the Lab Book lines ticked, then the document (with its PDF when kept) and the treatments and
    /// allergies ticked. Returns the saved document, nil when the file could not be written.
    func saveMedicalDocument(_ document: CoachMedicalDocument, pdf: Data?) async -> MedicalDocument? {
        if let lab = document.lab, lab.lines.contains(where: \.include) {
            _ = await saveLabReport(lab, nutritionKeys: [])
        }
        return MedicalFileStore.addMedicalDocument(document, pdf: pdf)
    }
}
