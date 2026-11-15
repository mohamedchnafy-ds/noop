import Foundation

// Personal fork, chantier 23: the medical file, on the iPhone only.
//
// The documents the user added (their PDF, kind, title, date and the Coach's factual summary), and the
// treatments and allergies they ticked from them, in one JSON file next to the PDFs in Application Support /
// MedicalFile. Outside the database and the `.noopbak` (like the Coach's photos): deleting a document deletes
// its PDF. The results and measurements a document prints go to the Lab Book instead, as Lab Book rows.
//
// The one store: the Medical file screen, the review sheet and the Coach's fiche read and write through here.

/// One document of the medical file.
struct MedicalDocument: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: MedicalDocumentKind
    var title: String
    /// YYYY-MM-DD, the day of the exam or visit.
    var day: String
    var summary: String
    /// Unix seconds it was added.
    var addedAt: Int
    /// The PDF kept with it, nil when the user chose not to keep it.
    var fileName: String?
}

/// Everything the medical file holds.
struct MedicalFileContent: Codable, Equatable, Sendable {
    var documents: [MedicalDocument] = []
    var treatments: [MedicalTreatment] = []
    var allergies: [MedicalAllergy] = []

    /// Newest first (the day, then when it was added).
    var sortedDocuments: [MedicalDocument] {
        documents.sorted { $0.day != $1.day ? $0.day > $1.day : $0.addedAt > $1.addedAt }
    }

    /// `items` added after the ones held, skipping a treatment whose name (and dose) is already there.
    mutating func mergeTreatments(_ items: [MedicalTreatment]) {
        for item in items {
            let key = MedicalFileStore.matchKey(item.name) + "|" + MedicalFileStore.matchKey(item.dose)
            if treatments.contains(where: {
                MedicalFileStore.matchKey($0.name) + "|" + MedicalFileStore.matchKey($0.dose) == key
            }) { continue }
            treatments.append(item)
        }
    }

    /// `items` added after the ones held, skipping a substance already there.
    mutating func mergeAllergies(_ items: [MedicalAllergy]) {
        for item in items {
            let key = MedicalFileStore.matchKey(item.substance)
            if allergies.contains(where: { MedicalFileStore.matchKey($0.substance) == key }) { continue }
            allergies.append(item)
        }
    }
}

enum MedicalFileStore {

    /// Bumped after every write, so the screens showing the file reload.
    static let revisionKey = "medicalFile.revision"

    /// Written whole, and on the iPhone readable only while it is unlocked.
    static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        return [.atomic]
        #endif
    }

    static let folderName = "MedicalFile"
    static let indexName = "medical-file.json"

    /// Application Support / MedicalFile, created when missing; nil when it cannot be.
    static func folder(fileManager: FileManager = .default) -> URL? {
        guard let base = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true) else { return nil }
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A name compared without case, accents or surrounding spaces.
    static func matchKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The file as stored; empty when there is none yet.
    static func loadMedicalFile(in folder: URL? = folder()) -> MedicalFileContent {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(indexName)),
              let content = try? JSONDecoder().decode(MedicalFileContent.self, from: data) else {
            return MedicalFileContent()
        }
        return content
    }

    @discardableResult
    static func saveMedicalFile(_ content: MedicalFileContent, in folder: URL? = folder()) -> Bool {
        guard let folder, let data = try? JSONEncoder().encode(content) else { return false }
        do {
            try data.write(to: folder.appendingPathComponent(indexName), options: writeOptions)
        } catch {
            return false
        }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
        return true
    }

    /// Where a document's PDF is, when it was kept and is still there.
    static func pdfURL(_ document: MedicalDocument, in folder: URL? = folder()) -> URL? {
        guard let folder, let name = document.fileName else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Add a reviewed document: its PDF (when `pdf` is given), its entry, and the treatments and allergies
    /// ticked. Returns the entry, nil when nothing could be written.
    @discardableResult
    static func addMedicalDocument(_ reviewed: CoachMedicalDocument, pdf: Data?, now: Date = Date(),
                                   in folder: URL? = folder()) -> MedicalDocument? {
        guard let folder else { return nil }
        let id = UUID().uuidString
        var fileName: String?
        if let pdf {
            let name = id + ".pdf"
            if (try? pdf.write(to: folder.appendingPathComponent(name), options: writeOptions)) != nil {
                fileName = name
            }
        }
        let document = MedicalDocument(id: id, kind: reviewed.kind, title: reviewed.title, day: reviewed.day,
                                       summary: reviewed.summary, addedAt: Int(now.timeIntervalSince1970),
                                       fileName: fileName)
        var content = loadMedicalFile(in: folder)
        content.documents.append(document)
        content.mergeTreatments(reviewed.treatments.filter(\.include).map { pick in
            var item = pick.item
            item.documentId = id
            return item
        })
        content.mergeAllergies(reviewed.allergies.filter(\.include).map { pick in
            var item = pick.item
            item.documentId = id
            return item
        })
        guard saveMedicalFile(content, in: folder) else { return nil }
        return document
    }

    /// Delete a document and its PDF (the treatments and allergies taken from it stay: they are the user's).
    static func removeMedicalDocument(id: String, in folder: URL? = folder()) {
        guard let folder else { return }
        var content = loadMedicalFile(in: folder)
        if let name = content.documents.first(where: { $0.id == id })?.fileName {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        content.documents.removeAll { $0.id == id }
        saveMedicalFile(content, in: folder)
    }

    static func removeTreatment(id: String, in folder: URL? = folder()) {
        var content = loadMedicalFile(in: folder)
        content.treatments.removeAll { $0.id == id }
        saveMedicalFile(content, in: folder)
    }

    static func removeAllergy(id: String, in folder: URL? = folder()) {
        var content = loadMedicalFile(in: folder)
        content.allergies.removeAll { $0.id == id }
        saveMedicalFile(content, in: folder)
    }

    /// Add a treatment or an allergy typed by hand.
    static func addTypedTreatment(name: String, dose: String, in folder: URL? = folder()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var content = loadMedicalFile(in: folder)
        content.mergeTreatments([MedicalTreatment(name: trimmed, dose: dose.trimmingCharacters(in: .whitespacesAndNewlines))])
        saveMedicalFile(content, in: folder)
    }

    static func addTypedAllergy(substance: String, in folder: URL? = folder()) {
        let trimmed = substance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var content = loadMedicalFile(in: folder)
        content.mergeAllergies([MedicalAllergy(substance: trimmed)])
        saveMedicalFile(content, in: folder)
    }

    /// What the Coach's fiche carries (with "Patterns and Lab Book" on): the treatments, the allergies and
    /// the latest documents' titles. Nil when the file is empty.
    static func ficheBlock(_ content: MedicalFileContent, maxDocuments: Int = 5) -> String? {
        guard !content.treatments.isEmpty || !content.allergies.isEmpty || !content.documents.isEmpty else { return nil }
        var lines = ["MEDICAL FILE (the user's own documents, copied as printed; not a diagnosis):"]
        lines.append("Treatments: " + (content.treatments.isEmpty ? "none recorded"
            : content.treatments.map(\.treatmentLine).joined(separator: "; ")))
        lines.append("Allergies: " + (content.allergies.isEmpty ? "none recorded"
            : content.allergies.map(\.allergyLine).joined(separator: "; ")))
        let latest = content.sortedDocuments.prefix(maxDocuments)
        if !latest.isEmpty {
            lines.append("Documents (get_medical_documents has the summaries): "
                         + latest.map { "\($0.day) \($0.kind.rawValue) \"\($0.title)\"" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    /// `get_medical_documents`: every document, newest first, with its summary.
    static func documentsToolText(_ content: MedicalFileContent) -> String {
        let documents = content.sortedDocuments
        guard !documents.isEmpty else { return "The medical file has no document." }
        var lines = ["The user's medical documents, newest first (summaries written when they were added, from "
                     + "the document as printed; not a diagnosis):"]
        for document in documents {
            lines.append("\(document.day) · \(document.kind.rawValue) · \(document.title)")
            if !document.summary.isEmpty { lines.append("  " + document.summary) }
        }
        return lines.joined(separator: "\n")
    }
}
