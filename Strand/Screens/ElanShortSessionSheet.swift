import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Élan · Séance courte (personal fork, chantier 10, PR C)
//
// The sheet the « Séance courte · 20 min » button opens (mockup v2.1 screen 7): the short session as the app
// built it (`ElanShortSession`: the program's first two blocks, each line with the sets and the load of its
// last session), « Démarrer maintenant » or « Ce soir · l'ajouter à aujourd'hui », what it counts for in the
// week, then « Ajuster avec le Coach » and « Garder au Carnet comme programme ». The Coach is called only
// from « Ajuster »; nothing here computes a figure of its own.

struct ElanShortSessionSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    let plan: ElanShortSessionPlan
    let unitSystem: UnitSystem
    /// The week's tally once this session is done tonight (« 2 / 3 »): done counts it, planned is the plan's.
    let weekDoneAfter: Int
    let weekPlanned: Int
    /// « Ce soir »: accepted for today.
    let onAccept: () -> Void
    /// « Démarrer maintenant »: accepted and started.
    let onStartNow: () -> Void

    /// The program the short session was saved as, once it was.
    @State private var savedProgramName: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    subtitle
                    sessionCard
                    countsCard
                    linksCard
                    Text("Built by the app, not by the Coach: the blocks of the missed program, in its order, with the sets and loads of the last session. The Coach is only called if you tap « Adjust ».")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, NoopVisualStyle.pagePadding)
                .padding(.bottom, NoopMetrics.space8)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Short session"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .tint(StrandPalette.accent)
    }

    @ViewBuilder
    private var subtitle: some View {
        Group {
            if plan.blocks.count >= 2 {
                Text("The first two blocks of \(plan.programName), with your loads from last time.")
            } else {
                Text("\(plan.programName), with your loads from last time.")
            }
        }
        .font(StrandFont.subhead)
        .foregroundStyle(StrandPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: The session

    private var sessionCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: plan.title)
                        .font(StrandFont.title2.weight(.bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if plan.estimatedMinutes > 0 {
                        Text("≈ \(plan.estimatedMinutes) min")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Text(verbatim: ElanShortSession.elanShapeLine(plan))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                ForEach(Array(plan.blocks.enumerated()), id: \.offset) { _, block in
                    blockCard(block)
                }
                ElanActionButton(title: Text("Start now"), look: .primary, systemImage: "play.fill") {
                    onStartNow()
                }
                ElanActionButton(title: Text("Tonight · add it to today"), look: .secondary) {
                    onAccept()
                }
            }
        }
    }

    private func blockCard(_ block: ElanShortBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if block.isSuperset, let letter = block.letter {
                Text("Superset \(letter)")
                    .font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            ForEach(Array(block.lines.enumerated()), id: \.offset) { _, line in
                lineRow(line)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }

    private func lineRow(_ line: ElanShortLine) -> some View {
        let targets = ElanShortSession.elanLineTargets(line, system: unitSystem)
        return HStack(spacing: 10) {
            if let tag = line.tag {
                Text(verbatim: tag)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 30, height: 22)
                    .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(verbatim: line.exercise)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(verbatim: targets.sets)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let load = targets.load {
                    Text(verbatim: "·")
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: load)
                        .fontWeight(.semibold)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            .font(StrandFont.subhead)
        }
        .frame(minHeight: 30)
    }

    // MARK: What it counts for

    private var countsCard: some View {
        NoopCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.elanSand)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text("Done tonight, it counts in your week:")
                        .foregroundStyle(StrandPalette.textSecondary)
                    if weekPlanned > 0 {
                        Text(verbatim: "\(weekDoneAfter) / \(weekPlanned)")
                            .fontWeight(.bold)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("sessions")
                            .foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text(verbatim: String(weekDoneAfter))
                            .fontWeight(.bold)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("sessions")
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .font(StrandFont.subhead)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Adjust · keep

    private var linksCard: some View {
        VStack(spacing: 0) {
            Button { adjustWithCoach() } label: {
                linkRow(Text("Adjust with the Coach"), detail: nil)
            }
            .buttonStyle(.plain)
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth).padding(.leading, 16)
            Button { Task { await keepAsProgram() } } label: {
                if let savedProgramName {
                    linkRow(Text("Kept in the Lift Log"), detail: Text(verbatim: savedProgramName))
                } else {
                    linkRow(Text("Keep in the Lift Log as a program"), detail: nil)
                }
            }
            .buttonStyle(.plain)
            .disabled(saving || savedProgramName != nil)
        }
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }

    private func linkRow(_ title: Text, detail: Text?) -> some View {
        HStack(spacing: 8) {
            title
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            if let detail {
                detail
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    /// Hands the short session to the Coach as a question, then opens the Coach (the shell closes this
    /// sheet and the one under it).
    private func adjustWithCoach() {
        let lines = plan.lines.map { line -> String in
            let targets = ElanShortSession.elanLineTargets(line, system: unitSystem)
            return [line.tag, line.exercise, targets.sets, targets.load].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: "; ")
        coach.pendingPrompt = String(localized: "Adjust this short session for tonight (\(plan.programName), about \(plan.estimatedMinutes) min): \(lines)")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            router.openCoach()
        }
    }

    /// Saves the short session as a program of its own: its lines, with the sets, reps, loads and rests it
    /// runs with, lettered as it shows them.
    @MainActor
    private func keepAsProgram() async {
        guard !saving, savedProgramName == nil, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        let programId = UUID().uuidString
        let labels = LiftSuperset.relabeled(plan.lines.map(\.item.supersetGroup))
        let items = plan.lines.enumerated().map { index, line in
            LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: programId, ord: index,
                               exercise: line.exercise, targetSets: line.sets,
                               targetRepsLow: line.reps ?? line.item.targetRepsLow,
                               targetRepsHigh: line.item.targetRepsHigh ?? line.reps,
                               targetRpe: line.item.targetRpe, targetWeightKg: line.weightKg,
                               restSec: line.restSec, note: line.item.note, supersetGroup: labels[index])
        }
        let row = LiftProgramRow(id: programId, deviceId: repo.deviceId, name: plan.title, note: nil,
                                 createdAt: now, updatedAt: now, archived: false)
        guard (try? await store.upsertLiftPrograms([row])) != nil,
              (try? await store.replaceLiftProgramItems(programId: programId, items: items)) != nil else { return }
        savedProgramName = plan.title
        await repo.refresh()
    }
}
