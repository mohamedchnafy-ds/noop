import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - The medical file (personal fork, chantier 23)
//
// « Medical file » (More → Health and recovery, and the Coach's "+"): the treatments and allergies the user
// keeps, and the documents they added with the Coach's summary and their PDF. Adding a PDF asks for the
// lab-report opt-in, sends the document, and opens the review sheet; nothing is saved before "Save".

/// The screen.
struct MedicalFileView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage(MedicalFileStore.revisionKey) private var revision = 0

    @State private var content = MedicalFileContent()
    @State private var importing = false
    @State private var opened: MedicalDocument?
    @State private var addingTreatment = false
    @State private var addingAllergy = false
    @State private var typedName = ""
    @State private var typedDose = ""

    var body: some View {
        ScreenScaffold(title: "Medical file",
                       subtitle: "Kept on this iPhone only. The Coach reads it with “Patterns and Lab Book” on.") {
            NoopButton("Add a PDF document", systemImage: "doc.badge.plus", kind: .primary, fullWidth: true) {
                importing = true
            }
            .disabled(!coach.canEstimateMeals)
            if !coach.canEstimateMeals {
                Text("Needs the Coach on, with Anthropic and your key.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }

            section(title: "Treatments", empty: "No treatment recorded.", isEmpty: content.treatments.isEmpty,
                    onAdd: { typedName = ""; typedDose = ""; addingTreatment = true }) {
                ForEach(content.treatments) { treatment in
                    itemRow(treatment.treatmentLine) { MedicalFileStore.removeTreatment(id: treatment.id) }
                }
            }
            section(title: "Allergies", empty: "No allergy recorded.", isEmpty: content.allergies.isEmpty,
                    onAdd: { typedName = ""; addingAllergy = true }) {
                ForEach(content.allergies) { allergy in
                    itemRow(allergy.allergyLine) { MedicalFileStore.removeAllergy(id: allergy.id) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                CoachSectionTitle("Documents")
                NoopCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        if content.documents.isEmpty {
                            Text("Add a lab report, a prescription, a consultation or imaging report: the Coach files it, you check it.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(content.sortedDocuments) { document in
                            if document.id != content.sortedDocuments.first?.id {
                                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                            }
                            Button { opened = document } label: { documentRow(document) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("Results and measurements go to the Lab Book. The PDF and this file stay out of the backup (.noopbak).")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: revision) { content = MedicalFileStore.loadMedicalFile() }
        .medicalDocumentImport(isPresented: $importing)
        .sheet(item: $opened) { document in
            MedicalDocumentDetail(document: document)
        }
        .alert("Add a treatment", isPresented: $addingTreatment) {
            TextField("Name", text: $typedName)
            TextField("Dose", text: $typedDose)
            Button("Add") { MedicalFileStore.addTypedTreatment(name: typedName, dose: typedDose) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add an allergy", isPresented: $addingAllergy) {
            TextField("Substance", text: $typedName)
            Button("Add") { MedicalFileStore.addTypedAllergy(substance: typedName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func section<Rows: View>(title: LocalizedStringKey, empty: LocalizedStringKey, isEmpty: Bool,
                                     onAdd: @escaping () -> Void, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CoachSectionTitle(title)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add"))
            }
            NoopCard(padding: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    if isEmpty {
                        Text(empty)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    rows()
                }
            }
        }
    }

    private func itemRow(_ text: String, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
    }

    private func documentRow(_ document: MedicalDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: document.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2)
                Text(verbatim: document.kind.kindTitle + " · " + MedicalFileFormat.documentDay(document.day))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

enum MedicalFileFormat {
    /// "3 oct. 2026" for a YYYY-MM-DD day; the key itself when it does not parse.
    static func documentDay(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(AppLanguage.activeLocale))
    }
}

/// One document: its summary, its PDF, and Delete.
struct MedicalDocumentDetail: View {
    let document: MedicalDocument

    @Environment(\.dismiss) private var dismiss
    @State private var showPDF = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text(verbatim: document.kind.kindTitle + " · " + MedicalFileFormat.documentDay(document.day))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    NoopCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary by the Coach")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text(verbatim: document.summary.isEmpty ? "—" : document.summary)
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if MedicalFileStore.pdfURL(document) != nil {
                        NoopButton("Open the PDF", systemImage: "doc.richtext", kind: .secondary, fullWidth: true) {
                            showPDF = true
                        }
                    } else {
                        Text("The PDF was not kept.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete the document", systemImage: "trash")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.statusCritical)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, 16)
            }
            .background(StrandPalette.surfaceRaised.ignoresSafeArea())
            .navigationTitle(Text(verbatim: document.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showPDF) {
                if let url = MedicalFileStore.pdfURL(document) {
                    MedicalPDFView(url: url)
                        .navigationTitle(Text(verbatim: document.title))
                }
            }
            .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    MedicalFileStore.removeMedicalDocument(id: document.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its PDF and summary are deleted. The treatments, allergies and Lab Book values taken from it stay.")
            }
        }
    }
}

#if canImport(PDFKit)
/// A kept PDF, shown with PDFKit.
struct MedicalPDFView: View {
    let url: URL

    var body: some View {
        PDFKitRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
    }
}

#if os(iOS)
private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#else
private struct PDFKitRepresentable: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif
#else
struct MedicalPDFView: View {
    let url: URL
    var body: some View { Text(verbatim: url.lastPathComponent) }
}
#endif

// MARK: - Adding a document

extension View {
    /// Adds a medical document when `isPresented` turns on: the opt-in when it is off, the file picker, the
    /// request, then the review sheet. `onSaved` runs with the saved document (the Coach fills its composer).
    func medicalDocumentImport(isPresented: Binding<Bool>,
                               onSaved: @escaping (MedicalDocument) -> Void = { _ in }) -> some View {
        modifier(MedicalDocumentImport(isPresented: isPresented, onSaved: onSaved))
    }
}

/// The reviewed document handed to the sheet, with the PDF it came from.
struct MedicalDocumentReview: Identifiable {
    let id = UUID()
    let document: CoachMedicalDocument
    let pdf: Data
}

struct MedicalDocumentImport: ViewModifier {
    @Binding var isPresented: Bool
    let onSaved: (MedicalDocument) -> Void

    @EnvironmentObject private var coach: AICoachEngine

    @State private var askConsent = false
    @State private var showingPicker = false   // macOS .fileImporter presentation
    @State private var reading = false
    @State private var review: MedicalDocumentReview?
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .onChangeCompat(of: isPresented) { asked in
                guard asked else { return }
                isPresented = false
                if coach.labReportConsent { pick() } else { askConsent = true }
            }
            .overlay(alignment: .bottom) {
                if reading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("The Coach is reading the document…")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(StrandPalette.surfaceRaised, in: Capsule())
                    .padding(.bottom, 24)
                }
            }
            .confirmationDialog("Send the whole document to Anthropic?", isPresented: $askConsent,
                                titleVisibility: .visible) {
                Button("Send the whole document") {
                    coach.labReportConsent = true
                    pick()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The PDF goes whole to Anthropic with your key, your identity, your doctor and the lab included, so the Coach can file it. You check each item before anything is saved. You can turn this off in What the coach reads.")
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { read(url) }
            }
            .sheet(item: $review) { item in
                MedicalDocumentReviewSheet(document: item.document) { reviewed, keepPDF in
                    if let saved = await coach.saveMedicalDocument(reviewed, pdf: keepPDF ? item.pdf : nil) {
                        onSaved(saved)
                    } else {
                        message = String(localized: "The document could not be saved.")
                    }
                }
            }
            .alert(Text("Medical file"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(verbatim: message ?? "")
            }
    }

    private func pick() {
        #if os(iOS)
        Task {
            guard let url = await DocumentPicker.importFile([.pdf]) else { return }
            read(url)
        }
        #else
        showingPicker = true
        #endif
    }

    private func read(_ url: URL) {
        reading = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                message = String(localized: "That file could not be read.")
                reading = false
                return
            }
            switch await coach.readMedicalDocument(pdf: data) {
            case .document(let document): review = MedicalDocumentReview(document: document, pdf: data)
            case .nothing(let said): message = said
            case .failure(let problem): message = problem.isEmpty ? nil : problem
            }
            reading = false
        }
    }
}

/// What the Coach filed, item by item: the document (kind, title, date, summary), the Lab Book values, the
/// treatments and allergies, and whether to keep the PDF. "Save" writes the ticked items.
struct MedicalDocumentReviewSheet: View {
    let onSave: (_ document: CoachMedicalDocument, _ keepPDF: Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var document: CoachMedicalDocument
    @State private var lab: CoachLabReport?
    @State private var nutrition: Set<String> = []
    @State private var keepPDF = true
    @State private var saving = false

    init(document: CoachMedicalDocument, onSave: @escaping (_ document: CoachMedicalDocument, _ keepPDF: Bool) async -> Void) {
        self.onSave = onSave
        _document = State(initialValue: document)
        _lab = State(initialValue: document.lab)
    }

    var body: some View {
        ScreenScaffold(title: "Check the document",
                       subtitle: "Filed by the Coach from your PDF. Nothing is saved until you save it.",
                       trailing: {
                           Button("Cancel") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                       }) {
            NoopCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(verbatim: document.title)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    } icon: {
                        Image(systemName: document.kind.symbol)
                            .foregroundStyle(StrandPalette.accent)
                    }
                    Text(verbatim: document.kind.kindTitle + " · " + MedicalFileFormat.documentDay(document.day))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if !document.summary.isEmpty {
                        Text(verbatim: document.summary)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle(isOn: $keepPDF) {
                        Text("Keep the PDF in the app")
                            .font(StrandFont.subhead)
                    }
                    .tint(StrandPalette.switchOn)
                }
            }
            if let labBinding = Binding($lab) {
                CoachSectionTitle("Results and measurements → Lab Book")
                LabReportReviewContent(report: labBinding, nutrition: $nutrition)
            }
            if !document.treatments.isEmpty {
                CoachSectionTitle("Treatments")
                NoopCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach($document.treatments) { $pick in
                            Toggle(isOn: $pick.include) {
                                Text(verbatim: pick.item.treatmentLine)
                                    .font(StrandFont.subhead)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .tint(StrandPalette.switchOn)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            if !document.allergies.isEmpty {
                CoachSectionTitle("Allergies")
                NoopCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach($document.allergies) { $pick in
                            Toggle(isOn: $pick.include) {
                                Text(verbatim: pick.item.allergyLine)
                                    .font(StrandFont.subhead)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .tint(StrandPalette.switchOn)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            NoopButton("Save", systemImage: "checkmark", kind: .primary, fullWidth: true) {
                saving = true
                var reviewed = document
                reviewed.lab = lab
                Task {
                    await onSave(reviewed, keepPDF)
                    if !nutrition.isEmpty { NutritionLabMarkers.addKeys(Array(nutrition)) }
                    saving = false
                    dismiss()
                }
            }
            .disabled(saving)
        }
    }
}
