import Foundation
import StrandImport
import WhoopStore
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - A lab report read by the Coach (personal fork, chantier 8)
//
// "Read a report with the Coach" in the Lab Book: one request outside any conversation, like the meal
// estimate. The PDF goes whole to Anthropic as a document block, only with the lab-report opt-in on; the model
// copies the results through `record_lab_values`; the review sheet shows them value by value and only "Add to
// Lab Book" writes. The PDF itself is never stored by the app, and nothing goes to the Coach's history.

/// How reading a report ended.
enum LabReportOutcome: Equatable {
    case report(CoachLabReport)
    /// The model found no result: its own sentence.
    case noValues(String)
    /// It could not run (opt-in off, key, size, network): a message to show.
    case failure(String)
}

extension AICoachEngine {

    /// Rounds before the last request forbids another call: one call is all it takes, one more to correct it.
    static let labReportRounds = 2

    /// Whether `pdf` fits what one request can carry; nil when it does, else the message to show.
    static func labReportSizeProblem(_ pdf: Data) -> String? {
        if pdf.count > CoachLabReport.maxBytes {
            return String(localized: "That PDF is too large to send (20 MB at most).")
        }
        #if canImport(PDFKit)
        if let document = PDFDocument(data: pdf), document.pageCount > CoachLabReport.maxPages {
            return String(localized: "That PDF has too many pages (100 at most).")
        }
        #endif
        return nil
    }

    /// Read the results of the lab report `pdf`, checked against the Lab Book rows already stored.
    func readLabReport(pdf: Data) async -> LabReportOutcome {
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
                ["type": "text", "text": "Copy the results of this lab report."] as [String: Any],
            ],
        ]
        var conversation: [[String: Any]] = [user]
        let system = CoachLabReport.systemPrompt(languageName: Self.mealEstimateLanguageName())
        var lastText = ""
        do {
            for round in 0...Self.labReportRounds {
                let allowTools = round < Self.labReportRounds
                let body = try AnthropicToolRequest.body(model: model, system: system, messages: conversation,
                                                         tools: [CoachLabReport.definition], allowTools: allowTools,
                                                         maxTokens: 16_000)
                let turn = try await streamToolRound(key: key, body: body) { _ in }
                lastText = turn.text
                guard allowTools, turn.stopReason == "tool_use", !turn.toolCalls.isEmpty else { break }
                var results: [(id: String, text: String, isError: Bool)] = []
                for call in turn.toolCalls {
                    guard call.name == CoachLabReport.toolName else {
                        results.append((call.id, "Unknown tool \(call.name).", true))
                        continue
                    }
                    let parsed = CoachLabReport.fromToolInput(CoachTools.input(fromJSON: call.inputJSON),
                                                              existing: existing, existingSource: Self.labSourceName)
                    if let report = parsed.report { return .report(report) }
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
        return .noValues(said.isEmpty ? String(localized: "No result was found in that document.") : said)
    }

    /// Where a Lab Book reading came from, as the review sheet names it.
    nonisolated static func labSourceName(_ source: String) -> String {
        switch source {
        case "manual": return String(localized: "entered by hand")
        case CoachLabReport.source: return String(localized: "lab report")
        case LabMarkerCsvImport.sourceId: return "CSV"
        case WhoopBiomarkerExportParser.sourceId: return "WHOOP"
        default: return source
        }
    }

    /// "Add to Lab Book": the ticked lines, then the markers ticked for Nutrition. Returns how many were written.
    func saveLabReport(_ report: CoachLabReport, nutritionKeys: [String]) async -> Int {
        let rows = report.labRows(deviceId: repo.deviceId)
        guard let store = await repo.storeHandle() else { return 0 }
        if !rows.isEmpty { _ = try? await store.upsertLabMarkers(rows) }
        NutritionLabMarkers.addKeys(nutritionKeys)
        await repo.refresh()
        return rows.count
    }
}
