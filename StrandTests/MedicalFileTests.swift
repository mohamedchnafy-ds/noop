import XCTest
@testable import Strand
import StrandImport
import WhoopStore

/// Fork chantier 23 (medical file): the document the Coach files (kind, title, date, summary, Lab Book lines,
/// treatments, allergies), the file kept in its own folder, duplicates skipped, and what the Coach reads.
@MainActor
final class MedicalFileTests: XCTestCase {

    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("medical-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private let prescription: [String: Any] = [
        "kind": "prescription",
        "title": "Ordonnance Dr Martin",
        "date": "2026-10-03",
        "summary": "Traitement de 7 jours après une angine.",
        "treatments": [["name": "Amoxicilline", "dose": "1 g", "schedule": "matin et soir, 7 jours"],
                       ["name": "  "]],
        "allergies": [["substance": "Pénicilline", "reaction": "urticaire"]],
        "values": [["name": "Tension", "value_text": "12/8", "unit": ""]],
    ]

    func testTheToolInputBecomesADocumentWithItsItemsTicked() throws {
        let parsed = CoachMedicalDocument.fromToolInput(prescription, existing: [])
        let document = try XCTUnwrap(parsed.document)
        XCTAssertNil(parsed.problem)
        XCTAssertEqual(document.kind, .prescription)
        XCTAssertEqual(document.title, "Ordonnance Dr Martin")
        XCTAssertEqual(document.day, "2026-10-03")
        XCTAssertEqual(document.treatments.count, 1, "a treatment without a name is dropped")
        XCTAssertEqual(document.treatments.first?.item.treatmentLine, "Amoxicilline · 1 g · matin et soir, 7 jours")
        XCTAssertEqual(document.treatments.first?.include, true)
        XCTAssertEqual(document.allergies.first?.item.allergyLine, "Pénicilline · urticaire")
        XCTAssertEqual(document.lab?.lines.count, 1, "results go to the Lab Book through the lab report")
        XCTAssertEqual(document.lab?.day, "2026-10-03")
    }

    func testABadDateOrNoTitleIsSentBackToTheModel() {
        var input = prescription
        input["date"] = "3 octobre"
        XCTAssertNil(CoachMedicalDocument.fromToolInput(input, existing: []).document)
        input["date"] = "2026-10-03"
        input["title"] = " "
        XCTAssertNotNil(CoachMedicalDocument.fromToolInput(input, existing: []).problem)
        input["title"] = "Bilan"
        input["kind"] = "not-a-kind"
        XCTAssertEqual(CoachMedicalDocument.fromToolInput(input, existing: []).document?.kind, .other)
    }

    func testSavingKeepsThePDFAndTheTickedItemsAndSkipsDuplicates() throws {
        var document = try XCTUnwrap(CoachMedicalDocument.fromToolInput(prescription, existing: []).document)
        let saved = try XCTUnwrap(MedicalFileStore.addMedicalDocument(document, pdf: Data("%PDF-1.4".utf8), in: folder))
        XCTAssertNotNil(MedicalFileStore.pdfURL(saved, in: folder))

        document.allergies[0].include = false
        document.treatments[0].item.name = "amoxicilline"   // the same treatment, another spelling
        let second = try XCTUnwrap(MedicalFileStore.addMedicalDocument(document, pdf: nil, in: folder))
        XCTAssertNil(MedicalFileStore.pdfURL(second, in: folder), "the PDF was not kept")

        let content = MedicalFileStore.loadMedicalFile(in: folder)
        XCTAssertEqual(content.documents.count, 2)
        XCTAssertEqual(content.treatments.count, 1, "the same treatment is not added twice")
        XCTAssertEqual(content.allergies.count, 1)
        XCTAssertEqual(content.treatments.first?.documentId, saved.id)

        MedicalFileStore.removeMedicalDocument(id: saved.id, in: folder)
        let after = MedicalFileStore.loadMedicalFile(in: folder)
        XCTAssertEqual(after.documents.map(\.id), [second.id])
        XCTAssertEqual(after.treatments.count, 1, "what was taken from a deleted document stays")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(saved.id + ".pdf").path))
    }

    func testTheCoachReadsTreatmentsAllergiesAndTheDocuments() throws {
        XCTAssertNil(MedicalFileStore.ficheBlock(MedicalFileContent()))
        let document = try XCTUnwrap(CoachMedicalDocument.fromToolInput(prescription, existing: []).document)
        MedicalFileStore.addMedicalDocument(document, pdf: nil, in: folder)
        let content = MedicalFileStore.loadMedicalFile(in: folder)
        let block = try XCTUnwrap(MedicalFileStore.ficheBlock(content))
        XCTAssertTrue(block.contains("Treatments: Amoxicilline · 1 g · matin et soir, 7 jours"), block)
        XCTAssertTrue(block.contains("Allergies: Pénicilline · urticaire"), block)
        XCTAssertTrue(block.contains("2026-10-03 prescription \"Ordonnance Dr Martin\""), block)
        let tool = MedicalFileStore.documentsToolText(content)
        XCTAssertTrue(tool.contains("Traitement de 7 jours après une angine."), tool)
        XCTAssertEqual(MedicalFileStore.documentsToolText(MedicalFileContent()), "The medical file has no document.")
    }

    func testTheToolDefinitionSerialises() throws {
        let definition = CoachMedicalDocument.definition
        XCTAssertEqual(definition["name"] as? String, "record_medical_document")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: definition))
        let schema = try XCTUnwrap(definition["input_schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["values"])
        XCTAssertNotNil(properties["treatments"])
    }
}
