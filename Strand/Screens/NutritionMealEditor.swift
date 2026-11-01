import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Add or edit a meal (personal fork, Nutrition mockup 2)
//
// Adding: the barcode, photo and dictation tiles (wired by the Coach steps), the recent meals (one tap adds
// one again, now), and the form to type a meal by hand: name, time, favourite, protein / carbs / fat and
// the calories, calculated from the macros (4 / 4 / 9) until the wearer types their own.
// Editing: the same form for a meal typed by hand; for a meal made of weighed foods (the Coach, a label),
// one line per food whose quantity can change, its values recalculated from the food's values per 100 g.
// Everything is written through `MealJournal`, so the numbers are rounded the way the journal rounds them.

enum NutritionEditorTarget: Identifiable {
    case add
    case edit(MealEntry)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let entry): return entry.meal.id
        }
    }
}

/// Reading what is typed into a number field: "28", "28,5" and "28.5" all read 28.5; empty or not a
/// number reads nil; a negative reads nil.
enum NutritionInput {
    static func typedNumber(_ text: String) -> Double? {
        let cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct NutritionMealEditor: View {
    let target: NutritionEditorTarget
    /// The journal day the meal goes to when it is added.
    let day: Date
    /// The tiles that hand over to the Coach or the scanner; nil shows the tile dimmed.
    var onBarcode: (() -> Void)? = nil
    var onPhoto: (() -> Void)? = nil
    var onDictate: (() -> Void)? = nil

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var eatenAt: Date
    @State private var favorite: Bool
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var kcalText: String
    /// True once the wearer typed the calories themselves.
    @State private var kcalTyped: Bool
    /// The foods of a weighed meal, and the quantity typed for each.
    @State private var lines: [MealItemRow]
    @State private var gramsTexts: [String: String]
    @State private var recents: [MealEntry] = []
    @State private var saving = false
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    init(target: NutritionEditorTarget, day: Date, onBarcode: (() -> Void)? = nil,
         onPhoto: (() -> Void)? = nil, onDictate: (() -> Void)? = nil) {
        self.target = target
        self.day = day
        self.onBarcode = onBarcode
        self.onPhoto = onPhoto
        self.onDictate = onDictate
        switch target {
        case .add:
            _name = State(initialValue: "")
            _eatenAt = State(initialValue: Self.defaultTime(on: day))
            _favorite = State(initialValue: false)
            _proteinText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _fatText = State(initialValue: "")
            _kcalText = State(initialValue: "")
            _kcalTyped = State(initialValue: false)
            _lines = State(initialValue: [])
            _gramsTexts = State(initialValue: [:])
        case .edit(let entry):
            _name = State(initialValue: entry.meal.name)
            _eatenAt = State(initialValue: Date(timeIntervalSince1970: TimeInterval(entry.meal.eatenAt)))
            _favorite = State(initialValue: entry.meal.favorite)
            let typed = Self.isTypedByHand(entry)
            let line = entry.items.first
            _proteinText = State(initialValue: typed ? (line.map { NutritionFormat.editable($0.nutrients.proteinG) } ?? "") : "")
            _carbsText = State(initialValue: typed ? (line.map { NutritionFormat.editable($0.nutrients.carbsG) } ?? "") : "")
            _fatText = State(initialValue: typed ? (line.map { NutritionFormat.editable($0.nutrients.fatG) } ?? "") : "")
            let kcal = line?.nutrients.kcal ?? 0
            let fromMacros = line.map { MealMath.kcal(proteinG: $0.nutrients.proteinG, carbsG: $0.nutrients.carbsG,
                                                      fatG: $0.nutrients.fatG) } ?? 0
            _kcalText = State(initialValue: typed && kcal != fromMacros ? String(kcal) : "")
            _kcalTyped = State(initialValue: typed && kcal != fromMacros)
            _lines = State(initialValue: typed ? [] : entry.items)
            var grams: [String: String] = [:]
            for item in entry.items { if let g = item.grams { grams[item.id] = NutritionFormat.editable(g) } }
            _gramsTexts = State(initialValue: grams)
        }
    }

    /// A meal typed by hand: one line, no food reference, no quantity.
    static func isTypedByHand(_ entry: MealEntry) -> Bool {
        entry.items.count == 1 && entry.items[0].per100 == nil && entry.items[0].grams == nil
    }

    /// Now on today; the same time of day on another day.
    static func defaultTime(on day: Date, now: Date = Date()) -> Date {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return now }
        let parts = cal.dateComponents([.hour, .minute], from: now)
        return cal.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private var editing: MealEntry? {
        if case .edit(let entry) = target { return entry }
        return nil
    }

    private var isWeighed: Bool { !lines.isEmpty }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var protein: Double { NutritionInput.typedNumber(proteinText) ?? 0 }
    private var carbs: Double { NutritionInput.typedNumber(carbsText) ?? 0 }
    private var fat: Double { NutritionInput.typedNumber(fatText) ?? 0 }
    private var macroKcal: Int { MealMath.kcal(proteinG: protein, carbsG: carbs, fatG: fat) }

    /// The calories saved for a meal typed by hand.
    private var typedKcal: Int {
        if kcalTyped, let typed = NutritionInput.typedNumber(kcalText) { return Int(typed.rounded()) }
        return macroKcal
    }

    /// The lines that will be saved for a weighed meal, recalculated from what is typed.
    private var weighedLines: [MealItemRow] {
        lines.map { line in
            guard let per100 = line.per100,
                  let typed = gramsTexts[line.id].flatMap(NutritionInput.typedNumber),
                  typed != line.grams else { return line }
            var row = MealJournal.measuredMealLine(name: line.name, grams: typed, estimated: false,
                                                   per100: per100, foodRef: line.foodRef)
            row.id = line.id
            return row
        }
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, !saving else { return false }
        if isWeighed { return !weighedLines.isEmpty }
        return typedKcal > 0 || protein + carbs + fat > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if editing == nil {
                        tiles
                        if !recents.isEmpty { recentSection }
                    }
                    formSection
                    if editing != nil { deleteButton }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(StrandPalette.surfaceRaised.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                NoopButton(editing == nil ? "Add to journal" : "Save",
                           systemImage: editing == nil ? "plus" : "checkmark",
                           kind: .primary, fullWidth: true) { save() }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.bottom, NoopMetrics.space2)
            }
            .navigationTitle(editing == nil ? Text("Add a meal") : Text("Edit meal"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, idealWidth: 520, minHeight: 600, idealHeight: 680)
        #endif
        .task {
            guard editing == nil, let store = await repo.storeHandle() else { return }
            recents = (try? await MealJournal.recentMealEntries(store, limit: 12)) ?? []
        }
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteMeal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from your journal.")
        }
    }

    // MARK: Adding

    private var tiles: some View {
        HStack(spacing: 8) {
            addTile(symbol: "barcode", title: "Barcode", detail: "label read by the Coach", action: onBarcode)
            addTile(symbol: "camera", title: "Photo", detail: "the Coach estimates it", action: onPhoto)
            addTile(symbol: "mic", title: "Dictate", detail: "estimated by the Coach", action: onDictate)
        }
    }

    private func addTile(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey,
                      action: (() -> Void)?) -> some View {
        Button {
            dismiss()
            action?()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(StrandFont.overlineScaled(11))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.45 : 1)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent meals").strandOverline()
                Spacer()
                Text("one tap adds it now")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            CoachChipFlow(spacing: 8) {
                ForEach(recents, id: \.meal.id) { entry in
                    recentChip(entry)
                }
            }
        }
    }

    private func recentChip(_ entry: MealEntry) -> some View {
        Button { addAgain(entry) } label: {
            HStack(spacing: 6) {
                if entry.meal.favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StrandPalette.onDarkSecondary)
                        .accessibilityLabel(Text("favorite"))
                }
                Text(verbatim: NutritionFormat.mealTitle(entry))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: NutritionFormat.mealKcal(entry))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(StrandPalette.surfaceOverlay, in: Capsule())
            .overlay(Capsule().strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .contextMenu {
            Button {
                setFavorite(entry, !entry.meal.favorite)
            } label: {
                Label(entry.meal.favorite ? "Remove from favorites" : "Add to favorites",
                      systemImage: entry.meal.favorite ? "star.slash" : "star")
            }
        }
    }

    // MARK: The form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing == nil { Text("By hand").strandOverline() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 8) {
                    editorField(title: "Name") {
                        TextField("", text: $name, prompt: Text("Pasta bolognese"))
                            .focused($focused)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meal time")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        DatePicker("Meal time", selection: $eatenAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(height: 44)
                    }
                    Button { favorite.toggle() } label: {
                        Image(systemName: favorite ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(favorite ? StrandPalette.onDarkSecondary : StrandPalette.textSecondary)
                            .frame(width: 44, height: 44)
                            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(favorite ? "Remove from favorites" : "Keep in favorites"))
                }
                if isWeighed {
                    weighedLinesSection
                } else {
                    macroFields
                    caloriesField
                }
            }
            .padding(14)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
        }
    }

    private var macroFields: some View {
        HStack(spacing: 8) {
            editorMacroField(.protein, title: "Protein (g)", text: $proteinText)
            editorMacroField(.carbs, title: "Carbs (g)", text: $carbsText)
            editorMacroField(.fat, title: "Fat (g)", text: $fatText)
        }
    }

    private func editorMacroField(_ macro: NutritionMacro, title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                NutritionMacroDot(macro: macro, size: 7)
                Text(title)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            numberField(text: text, prompt: "0")
        }
    }

    private var caloriesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calories")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 6) {
                TextField("", text: Binding(
                    get: { kcalTyped ? kcalText : (macroKcal > 0 ? String(macroKcal) : "") },
                    set: { value in
                        kcalText = value
                        kcalTyped = NutritionInput.typedNumber(value) != nil
                    }), prompt: Text(verbatim: "0"))
                    .font(StrandFont.number(16))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text(verbatim: "kcal")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
            Text(verbatim: caloriesCaption)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "calculated from the macros (4 × 28 + 4 × 85 + 9 × 16), editable", or what the macros give when
    /// the calories were typed.
    private var caloriesCaption: String {
        if kcalTyped {
            return String(localized: "typed by hand · the macros give \(NutritionFormat.whole(macroKcal)) kcal")
        }
        let formula = "4 × \(NutritionFormat.editable(protein)) + 4 × \(NutritionFormat.editable(carbs)) + 9 × \(NutritionFormat.editable(fat))"
        return String(localized: "calculated from the macros (\(formula)), editable")
    }

    private var weighedLinesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Foods")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.bottom, 6)
            ForEach(Array(weighedLines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                }
                weighedLine(line)
            }
            let total = MealMath.totals(weighedLines.map(\.nutrients))
            HStack {
                Text("Total")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(verbatim: NutritionFormat.kcalAndMacros(total))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.top, 10)
        }
    }

    private func weighedLine(_ line: MealItemRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.name)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2)
                Text(verbatim: NutritionFormat.kcalAndMacros(line.nutrients))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if line.per100 != nil {
                HStack(spacing: 4) {
                    numberField(text: Binding(get: { gramsTexts[line.id] ?? "" },
                                              set: { gramsTexts[line.id] = $0 }), prompt: "0")
                        .frame(width: 76)
                    Text(verbatim: "g")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .accessibilityLabel(Text("Quantity of \(line.name) in grams"))
            }
            if lines.count > 1 {
                Button {
                    lines.removeAll { $0.id == line.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(line.name)"))
            }
        }
        .padding(.vertical, 8)
    }

    private func editorField<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            content()
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberField(text: Binding<String>, prompt: String) -> some View {
        TextField("", text: text, prompt: Text(verbatim: prompt))
            .font(StrandFont.bodyNumber)
            .foregroundStyle(StrandPalette.textPrimary)
            .focused($focused)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
    }

    private var deleteButton: some View {
        NoopButton("Delete meal", systemImage: "trash", kind: .tertiary, fullWidth: true) {
            confirmDelete = true
        }
    }

    // MARK: Writing

    private func save() {
        guard canSave else { return }
        saving = true
        let name = trimmedName
        let lines: [MealItemRow] = isWeighed
            ? weighedLines
            : [MealJournal.typedMealLine(name: name, proteinG: protein, carbsG: carbs, fatG: fat,
                                         kcal: kcalTyped ? typedKcal : nil)]
        let origin = editing?.meal.origin ?? .manual
        let id = editing?.meal.id
        let when = eatenAt
        let favorite = favorite
        Task {
            defer { saving = false }
            guard let store = await repo.storeHandle() else { return }
            do {
                try await MealJournal.saveMealEntry(store, id: id, name: name, origin: origin, eatenAt: when,
                                                    favorite: favorite, lines: lines)
                dismiss()
            } catch {
                // Nothing was written: the form stays open with what was typed.
            }
        }
    }

    private func addAgain(_ entry: MealEntry) {
        saving = true
        let when = Self.defaultTime(on: day)
        Task {
            defer { saving = false }
            guard let store = await repo.storeHandle() else { return }
            if (try? await MealJournal.addMealAgain(store, entry, eatenAt: when)) != nil { dismiss() }
        }
    }

    private func setFavorite(_ entry: MealEntry, _ value: Bool) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await MealJournal.markMealFavorite(store, id: entry.meal.id, favorite: value)
            recents = (try? await MealJournal.recentMealEntries(store, limit: 12)) ?? recents
        }
    }

    private func deleteMeal() {
        guard let id = editing?.meal.id else { return }
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await MealJournal.removeMeal(store, id: id)
            dismiss()
        }
    }
}
