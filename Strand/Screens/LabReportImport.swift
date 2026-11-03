import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport

/// "Read a PDF report with the Coach" in the Lab Book's import card (personal fork, chantier 8). Asks for the
/// lab-report opt-in when it is off (the document goes whole to Anthropic), then sends the PDF the user picks
/// and opens the review sheet; nothing is written before "Add to Lab Book" there.
struct LabReportImportRow: View {
    /// Called once readings were added, so the Lab Book reloads.
    let onSaved: () async -> Void

    @EnvironmentObject var coach: AICoachEngine

    @State private var askConsent = false
    @State private var showingPicker = false   // macOS .fileImporter presentation
    @State private var reading = false
    @State private var review: LabReportReview?
    @State private var message: String?

    init(onSaved: @escaping () async -> Void) {
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    start()
                } label: {
                    // An `if`, not a ternary: `Label(cond ? "a" : "b")` picks the untranslated String overload.
                    if reading {
                        Label("Reading the report…", systemImage: "doc.text.magnifyingglass")
                    } else {
                        Label("Read a PDF report with the Coach", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .buttonStyle(.noopSecondary)
                .disabled(reading || !coach.canEstimateMeals)
                if reading { ProgressView().controlSize(.small) }
            }
            if !coach.canEstimateMeals {
                Text("Needs the Coach on, with Anthropic and your key.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let message {
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Send the whole report to Anthropic?", isPresented: $askConsent, titleVisibility: .visible) {
            Button("Send the whole document") {
                coach.labReportConsent = true
                pick()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The PDF goes whole to Anthropic with your key, your identity, your doctor and the lab included, so the Coach can copy its results. You check each value before anything is saved. You can turn this off in What the coach reads.")
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { read(url) }
        }
        .sheet(item: $review) { item in
            LabReportReviewSheet(report: item.report) { report, nutrition in
                let written = await coach.saveLabReport(report, nutritionKeys: nutrition)
                message = written == 1 ? String(localized: "1 reading added to the Lab Book.")
                                       : String(localized: "\(written) readings added to the Lab Book.")
                await onSaved()
            }
        }
    }

    private func start() {
        message = nil
        if coach.labReportConsent { pick() } else { askConsent = true }
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
            switch await coach.readLabReport(pdf: data) {
            case .report(let report): review = LabReportReview(report: report)
            case .noValues(let said): message = said
            case .failure(let problem): message = problem.isEmpty ? nil : problem
            }
            reading = false
        }
    }
}

/// The report handed to the review sheet.
struct LabReportReview: Identifiable {
    let id = UUID()
    let report: CoachLabReport
}

/// Each value the Coach copied, ticked or not, with the report's own unit and range; a reading the Lab Book
/// already holds that day is flagged and left unticked. "Add to Lab Book" writes the ticked ones.
struct LabReportReviewSheet: View {
    let onSave: (_ report: CoachLabReport, _ nutritionKeys: [String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var report: CoachLabReport
    @State private var nutrition: Set<String> = []
    @State private var saving = false

    init(report: CoachLabReport, onSave: @escaping (_ report: CoachLabReport, _ nutritionKeys: [String]) async -> Void) {
        self.onSave = onSave
        _report = State(initialValue: report)
    }

    private var ticked: Int { report.lines.filter(\.include).count }

    /// "Add 3 values to Lab Book"; only the Nutrition choice when nothing is ticked.
    private var addTitle: LocalizedStringKey {
        if ticked == 0 { return "Show in Nutrition" }
        if ticked == 1 { return "Add 1 value to Lab Book" }
        return "Add \(ticked) values to Lab Book"
    }

    var body: some View {
        ScreenScaffold(title: "Check the values",
                       subtitle: "Copied by the Coach from your report. Nothing is saved until you add them.",
                       trailing: {
                           Button("Cancel") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accent)
                       }) {
            Text(verbatim: reportDay)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            NoopCard(padding: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach($report.lines) { $line in
                        lineRow($line)
                        if line.id != report.lines.last?.id {
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        }
                    }
                }
            }
            if !report.nutritionSuggestions.isEmpty {
                CoachSectionTitle("Show in Nutrition")
                NoopCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The Coach suggests following these in Nutrition too, beside vitamin D, ferritin, B12 and HbA1c.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(report.nutritionSuggestions, id: \.self) { key in
                            Toggle(isOn: Binding(get: { nutrition.contains(key) },
                                                 set: { on in if on { nutrition.insert(key) } else { nutrition.remove(key) } })) {
                                Text(verbatim: MarkerCatalog.definition(for: key)?.displayName ?? key)
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                            }
                            .toggleStyle(.switch)
                            .tint(StrandPalette.accent)
                        }
                    }
                }
            }
            Text("Values and units are kept as printed. NOOP gives no verdict on a result: ask your doctor.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            NoopButton(addTitle, systemImage: "plus", kind: .primary, fullWidth: true) {
                saving = true
                Task {
                    await onSave(report, Array(nutrition))
                    saving = false
                    dismiss()
                }
            }
            .disabled(saving || (ticked == 0 && nutrition.isEmpty))
        }
    }

    private var reportDay: String {
        guard let date = LabReportReviewSheet.dayParser.date(from: report.day) else { return report.day }
        return date.formatted(date: .long, time: .omitted)
    }

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func lineRow(_ line: Binding<CoachLabReport.Line>) -> some View {
        Toggle(isOn: line.include) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: MarkerCatalog.definition(for: line.wrappedValue.markerKey)?.displayName
                     ?? line.wrappedValue.printedName)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: line.wrappedValue.valueLine)
                    .font(StrandFont.subhead.monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
                if let reference = line.wrappedValue.referenceText {
                    Text("Report's range: \(reference)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let existing = line.wrappedValue.existing {
                    Text("Already in the Lab Book that day: \(existing)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(StrandPalette.accent)
        .padding(.vertical, 10)
    }
}
