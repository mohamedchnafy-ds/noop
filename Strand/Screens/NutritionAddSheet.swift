import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Add to a moment (fork chantier 9, Nutrition mockup 4)
//
// The sheet the "+" of a moment opens, and the search field at the top of Nutrition: the moment the meal
// goes to (changeable), a search over the journal's foods and the Ciqual table as the wearer types (Open
// Food Facts only on the tap of its line), the four other ways in (Scan, Photo, Dictate, Type in), and the
// recent meals to add again in one tap. A food picked opens its portion, then "Add to journal". Every
// figure is computed by the app (`NutritionFoodSearch`, `MealJournal`).

/// What the sheet hands back to the screen, which opens it once the sheet has closed.
enum NutritionAddAction: Equatable {
    case scan, photo, dictate, type
}

struct NutritionAddSheet: View {
    /// The journal day the meal goes to.
    let day: Date
    let initialSlot: MealSlot
    /// Opened from the search field: the keyboard comes up at once.
    var focusSearch = false
    var canScan = false
    var canEstimate = false
    /// One of the four other ways in, with the moment chosen: the screen opens it after the sheet closes.
    var onAction: (NutritionAddAction, MealSlot) -> Void = { _, _ in }

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OpenFoodFacts.enabledKey) private var openFoodFactsOn = true

    @State private var slot: MealSlot
    @State private var query = ""
    @State private var hits: [NutritionFoodHit] = []
    @State private var journalFoods: [NutritionFoodHit] = []
    @State private var recents: [MealEntry] = []
    @State private var picked: NutritionFoodHit?
    @State private var offState: OffState = .idle
    @State private var saving = false
    @FocusState private var searchFocused: Bool

    /// The Open Food Facts line: not asked yet, asking, its products for the words asked, or no answer.
    private enum OffState: Equatable {
        case idle
        case loading(String)
        case found(String, [NutritionFoodHit])
        case unreachable(String)
    }

    init(day: Date, initialSlot: MealSlot, focusSearch: Bool = false, canScan: Bool = false,
         canEstimate: Bool = false, onAction: @escaping (NutritionAddAction, MealSlot) -> Void = { _, _ in }) {
        self.day = day
        self.initialSlot = initialSlot
        self.focusSearch = focusSearch
        self.canScan = canScan
        self.canEstimate = canEstimate
        self.onAction = onAction
        _slot = State(initialValue: initialSlot)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    NutritionSlotChips(selection: $slot)
                    if trimmedQuery.isEmpty {
                        NutritionAddTiles(onScan: canScan ? { hand(.scan) } : nil,
                                          onPhoto: canEstimate ? { hand(.photo) } : nil,
                                          onDictate: canEstimate ? { hand(.dictate) } : nil,
                                          onType: { hand(.type) })
                        if !recents.isEmpty { recentSection }
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(StrandPalette.surfaceRaised.ignoresSafeArea())
            .navigationTitle(Text("Add · \(NutritionSlot.slotTitle(slot))"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .navigationDestination(isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } })) {
                if let hit = picked {
                    NutritionPortionScreen(hit: hit, slot: slot, saving: saving) { grams in add(hit, grams: grams) }
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, idealWidth: 520, minHeight: 600, idealHeight: 680)
        #endif
        .task {
            if focusSearch { searchFocused = true }
            guard let store = await repo.storeHandle() else { return }
            recents = (try? await MealJournal.recentMealEntries(store, limit: 8)) ?? []
            journalFoods = await NutritionFoodSearch.loadJournalFoods(store)
        }
        .task(id: "\(trimmedQuery)|\(journalFoods.count)") {
            let text = trimmedQuery
            guard !text.isEmpty else { hits = []; return }
            // A short pause, so the table is searched once the typing settles.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let limit = NutritionFoodSearch.ciqualLimit
            let table = await Task.detached(priority: .userInitiated) { CiqualTable.search(text, limit: limit) }.value
            guard !Task.isCancelled else { return }
            hits = NutritionFoodSearch.searchFoodHits(text, journal: journalFoods, ciqual: table)
        }
    }

    // MARK: Parts

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search a food"))
                .focused($searchFocused)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent meals").strandOverline()
            VStack(spacing: 0) {
                ForEach(Array(recents.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { NutritionHairline() }
                    Button {
                        addAgain(entry)
                    } label: {
                        HStack(spacing: 10) {
                            Text(verbatim: NutritionFormat.mealTitle(entry))
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: NutritionFormat.mealKcal(entry))
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .monospacedDigit()
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(StrandPalette.intakeColor)
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityHint(Text("Adds it again now"))
                }
            }
            .padding(.horizontal, 14)
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text("No food found in your journal or the Ciqual table.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
            ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
                if index > 0 { NutritionHairline() }
                NutritionFoodHitRow(hit: hit) { picked = hit }
            }
        }
        .padding(.horizontal, 14)
        .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        if openFoodFactsOn { offSection }
        Text("Food values: \(CiqualTable.attribution)")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The Open Food Facts line: one request, only on its tap, for the words typed then.
    @ViewBuilder
    private var offSection: some View {
        let text = trimmedQuery
        switch offState {
        case .found(let asked, let products) where asked == text:
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: OpenFoodFacts.attribution)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.top, 10)
                if products.isEmpty {
                    Text("No product found on Open Food Facts.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.vertical, 12)
                }
                ForEach(Array(products.enumerated()), id: \.offset) { index, hit in
                    if index > 0 { NutritionHairline() }
                    NutritionFoodHitRow(hit: hit) { picked = hit }
                }
            }
            .padding(.horizontal, 14)
            .background(StrandPalette.surfaceBase, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .loading(let asked) where asked == text:
            HStack(spacing: 8) {
                ProgressView()
                Text("Asking Open Food Facts…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(minHeight: 44)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    searchOpenFoodFacts(text)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .accessibilityHidden(true)
                        Text("Search “\(text)” on Open Food Facts")
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if case .unreachable(let asked) = offState, asked == text {
                    Text("Open Food Facts did not answer (no network?). Try again later.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Only the words typed are sent, to the open food database (no account).")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Actions

    private func hand(_ action: NutritionAddAction) {
        onAction(action, slot)
        dismiss()
    }

    private func searchOpenFoodFacts(_ text: String) {
        guard !text.isEmpty else { return }
        offState = .loading(text)
        Task {
            switch await OpenFoodFacts.searchProducts(terms: text) {
            case .found(let products):
                offState = .found(text, products.map(NutritionFoodSearch.productHit))
            case .unreachable:
                offState = .unreachable(text)
            }
        }
    }

    private func add(_ hit: NutritionFoodHit, grams: Double) {
        guard !saving else { return }
        saving = true
        let when = NutritionMealEditor.defaultTime(on: day)
        let slot = slot
        Task {
            defer { saving = false }
            guard let store = await repo.storeHandle() else { return }
            let saved = try? await MealJournal.saveMealEntry(
                store, name: hit.name, origin: NutritionFoodSearch.hitOrigin(hit), eatenAt: when, slot: slot,
                lines: [NutritionFoodSearch.hitLine(hit, grams: grams)])
            if saved != nil { dismiss() }
        }
    }

    private func addAgain(_ entry: MealEntry) {
        guard !saving else { return }
        saving = true
        let when = NutritionMealEditor.defaultTime(on: day)
        let slot = slot
        Task {
            defer { saving = false }
            guard let store = await repo.storeHandle() else { return }
            if (try? await MealJournal.addMealAgain(store, entry, eatenAt: when, slot: slot)) != nil { dismiss() }
        }
    }
}

/// The four moments as chips, the chosen one white (the sheet's moment). A pure view.
struct NutritionSlotChips: View {
    @Binding var selection: MealSlot

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MealSlot.allCases, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(verbatim: NutritionSlot.slotTitle(item))
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(item == selection ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(item == selection ? StrandPalette.textPrimary : StrandPalette.surfaceBase))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selection ? .isSelected : [])
            }
        }
    }
}

/// One food of the search: its name, where it comes from and its values for 100 g, a chevron.
struct NutritionFoodHitRow: View {
    let hit: NutritionFoodHit
    let onPick: () -> Void

    private var sourceText: String {
        switch hit.source {
        case .journal:
            if let grams = hit.lastGrams { return String(localized: "in your journal · last time \(NutritionFormat.editable(grams)) g") }
            return String(localized: "in your journal")
        case .ciqual: return "Ciqual"
        case .openFoodFacts: return "Open Food Facts"
        }
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: hit.name)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                    Text(verbatim: sourceText + " · " + NutritionFormat.per100Line(hit.per100))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The portion of a food picked in the search, pushed in the sheet.
struct NutritionPortionScreen: View {
    let hit: NutritionFoodHit
    let slot: MealSlot
    let saving: Bool
    let onAdd: (Double) -> Void

    @State private var grams: Double

    init(hit: NutritionFoodHit, slot: MealSlot, saving: Bool, onAdd: @escaping (Double) -> Void) {
        self.hit = hit
        self.slot = slot
        self.saving = saving
        self.onAdd = onAdd
        _grams = State(initialValue: NutritionFoodSearch.startingPortion(hit))
    }

    var body: some View {
        ScrollView {
            NutritionPortionPanel(hit: hit, slot: slot, grams: $grams, saving: saving, onAdd: { onAdd(grams) })
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, 16)
        }
        .background(StrandPalette.surfaceRaised.ignoresSafeArea())
        .navigationTitle(Text("Portion"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The portion card: the food, its values for 100 g, − / + 10 g, quick choices, the portion's total and
/// "Add to journal" in the moment chosen. A pure view (rendered in PNG).
struct NutritionPortionPanel: View {
    let hit: NutritionFoodHit
    let slot: MealSlot
    @Binding var grams: Double
    let saving: Bool
    let onAdd: () -> Void

    var body: some View {
        let portion = MealMath.portion(per100: hit.per100, grams: grams)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: hit.name)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: NutritionSlot.slotTitle(slot))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            HStack(spacing: 8) {
                Text("Per 100 g")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: NutritionFormat.per100Line(hit.per100))
                    .font(StrandFont.footnote.monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 12) {
                stepButton(symbol: "minus", label: "Less", enabled: grams > 1) {
                    grams = MealJournal.clampedPortion(grams - BarcodeCatalog.portionStep)
                }
                Text(verbatim: NutritionFormat.portionGrams(grams, estimated: false))
                    .font(StrandFont.number(24, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                stepButton(symbol: "plus", label: "More", enabled: grams < 2_000) {
                    grams = MealJournal.clampedPortion(grams + BarcodeCatalog.portionStep)
                }
            }
            HStack(spacing: 8) {
                ForEach(BarcodeCatalog.portionChoices(lastGrams: hit.lastGrams), id: \.self) { choice in
                    Button {
                        grams = choice
                    } label: {
                        Text(verbatim: NutritionFormat.portionGrams(choice, estimated: false))
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(choice == grams ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(choice == grams ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                    }
                    .buttonStyle(.plain)
                }
            }
            MealTotalsRow(total: portion)
                .padding(.horizontal, NoopMetrics.space3)
                .padding(.vertical, 10)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            NoopButton("Add to journal", systemImage: "plus", kind: .primary, fullWidth: true, action: onAdd)
                .disabled(saving)
        }
        .padding(18)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    private func stepButton(symbol: String, label: LocalizedStringKey, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(StrandPalette.surfaceOverlay, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }
}

/// A hairline between two rows of a card.
struct NutritionHairline: View {
    var body: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }
}
