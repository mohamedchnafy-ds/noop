import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Habits: the sheets (personal fork, chantier 24, PR B)
//
// After a stop (a note, Resume, Don't keep), a session entered or corrected by hand, and a habit
// created or edited. The sheets only collect values: every write goes through `HabitLog`, which also
// decides whether a session can be saved (`HabitSessionProblem`).

/// What follows « Stop »: the session is already saved when this opens (the stopwatch stopped at the
/// tap), so closing the sheet keeps it with no note.
struct HabitStopSheet: View {
    let habitName: String
    let session: HabitSessionRow
    let onSaveNote: (String) -> Void
    let onResume: () -> Void
    let onDiscard: () -> Void
    @State private var note = ""
    @State private var confirmsDiscard = false

    private var seconds: Int { HabitLog.habitSessionSeconds(session, nowSec: session.endedAt ?? session.startedAt) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(verbatim: [habitName, HabitFormat.sessionWhen(session)].joined(separator: " · "))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(verbatim: HabitFormat.duration(seconds: seconds))
                        .font(StrandFont.number(40, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                TextField("A note? (optional) e.g. hard to focus, too tired.", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .font(StrandFont.body)
                    .padding(12)
                    .background(StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                FastingActionButton(title: Text("Save"), look: .primary) { onSaveNote(note) }
                HStack {
                    Button("Resume", action: onResume)
                        .foregroundStyle(StrandPalette.accent)
                    Spacer()
                    Button("Don't keep") { confirmsDiscard = true }
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                .font(StrandFont.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, 8)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Session over"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(Text("Delete this session?"), isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Delete the session", role: .destructive, action: onDiscard)
                Button("Cancel", role: .cancel) {}
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// A session entered by hand (`session` nil) or corrected. A running session shows no end: only its
/// start and its note change. `onSave` returns why the store refused (an overlap), shown under the
/// fields; nil closes the sheet.
struct HabitSessionEditor: View {
    let habitName: String
    let session: HabitSessionRow?
    let onSave: (_ start: Date, _ end: Date?, _ note: String) async -> HabitSessionProblem?
    let onDelete: () -> Void
    let onCancel: () -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var refusal: HabitSessionProblem?
    @State private var saving = false
    @State private var confirmsDelete = false

    init(habitName: String, session: HabitSessionRow?, now: Date = Date(),
         onSave: @escaping (_ start: Date, _ end: Date?, _ note: String) async -> HabitSessionProblem?,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.habitName = habitName
        self.session = session
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let startSec = session?.startedAt ?? Int(now.addingTimeInterval(-30 * 60).timeIntervalSince1970)
        let endSec = session?.endedAt ?? Int(now.timeIntervalSince1970)
        _start = State(initialValue: Date(timeIntervalSince1970: TimeInterval(startSec)))
        _end = State(initialValue: Date(timeIntervalSince1970: TimeInterval(max(endSec, startSec))))
        _note = State(initialValue: session?.note ?? "")
    }

    private var isRunning: Bool { session != nil && session?.endedAt == nil }

    /// What the fields alone already refuse (the overlap needs the store, checked on save).
    private var localProblem: HabitSessionProblem? {
        if isRunning { return start > Date() ? .inFuture : nil }
        return HabitLog.habitSessionProblem(startSec: Int(start.timeIntervalSince1970),
                                            endSec: Int(end.timeIntervalSince1970), others: [], editingId: nil,
                                            nowSec: Int(Date().timeIntervalSince1970) + 59)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: habitName)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    VStack(spacing: 0) {
                        DatePicker("Start time", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .padding(.vertical, 6)
                        if !isRunning {
                            Divider()
                            DatePicker("End time", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .padding(.vertical, 6)
                            Divider()
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text(verbatim: HabitFormat.duration(seconds: max(0, Int(end.timeIntervalSince(start)))))
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .font(StrandFont.body)
                    .padding(.horizontal, 14)
                    .background(StrandPalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .font(StrandFont.body)
                        .padding(12)
                        .background(StrandPalette.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if let problem = localProblem ?? refusal {
                        Text(verbatim: HabitFormat.problemText(problem))
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if session != nil {
                        Button("Delete the session", role: .destructive) { confirmsDelete = true }
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, 8)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(session == nil ? Text("Add a session") : Text("Habit session"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if session == nil { Text("Add") } else { Text("Save") }
                    }
                    .disabled(localProblem != nil || saving)
                }
            }
            .onChange(of: start) { _ in refusal = nil }
            .onChange(of: end) { _ in refusal = nil }
            .confirmationDialog(Text("Delete this session?"), isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete the session", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        saving = true
        Task { @MainActor in
            refusal = await onSave(start, isRunning ? nil : end, note)
            saving = false
        }
    }
}

/// A habit created (`habit` nil) or edited: its name, colour and icon; deleting it names how many
/// sessions go with it.
struct HabitEditor: View {
    let habit: HabitRow?
    let sessionCount: Int
    let onSave: (_ name: String, _ colorKey: String, _ symbol: String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var colorKey: String
    @State private var symbol: String
    @State private var confirmsDelete = false

    init(habit: HabitRow?, sessionCount: Int,
         onSave: @escaping (_ name: String, _ colorKey: String, _ symbol: String) -> Void,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.habit = habit
        self.sessionCount = sessionCount
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: habit?.name ?? "")
        _colorKey = State(initialValue: habit?.colorKey ?? HabitPalette.defaultKey)
        _symbol = State(initialValue: habit?.symbol ?? HabitPalette.symbols[0])
    }

    private var canSave: Bool { HabitLog.storedHabitName(name) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HabitIconTile(symbol: symbol, colorKey: colorKey, size: 44)
                        TextField("Name (e.g. Reading)", text: $name)
                            .font(StrandFont.body)
                    }
                    .padding(12)
                    .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Colour")
                        .font(StrandFont.footnote.weight(.medium))
                        .foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: 12) {
                        ForEach(HabitLog.colorKeys, id: \.self) { key in
                            Button { colorKey = key } label: {
                                Circle()
                                    .fill(HabitPalette.tint(key))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(StrandPalette.textPrimary,
                                                                   lineWidth: key == colorKey ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(key == colorKey ? .isSelected : [])
                        }
                    }
                    Text("Icon")
                        .font(StrandFont.footnote.weight(.medium))
                        .foregroundStyle(StrandPalette.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(HabitPalette.symbols, id: \.self) { item in
                            Button { symbol = item } label: {
                                Image(systemName: item)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(item == symbol ? HabitPalette.tint(colorKey) : StrandPalette.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(StrandPalette.surfaceRaised,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(StrandPalette.textPrimary, lineWidth: item == symbol ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(item == symbol ? .isSelected : [])
                        }
                    }
                    if habit != nil {
                        Button("Delete the habit", role: .destructive) { confirmsDelete = true }
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, 8)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(habit == nil ? Text("New habit") : Text("Edit the habit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(name, colorKey, symbol) }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(Text("Delete \(habit?.name ?? "") and its \(sessionCount) sessions?"),
                                isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete the habit", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
