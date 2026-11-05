import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

// MARK: - More sheet (fork chantier 9, section 7)
//
// Mockup « Plus » (validated 4 Nov.): ONE list in sections instead of four groups on two levels. The
// profile card (the Coach's first name, the strap, its charge, the last sync; a tap opens Settings), then
// Health & recovery, Analysis (Trends alone) and Data & settings, each row with its value on the right when
// it helps (Vitality, stress now, the last lab entry, the next alarm, the last backup), then « Advanced »,
// folded, with the fifteen other screens. Nothing was removed. Shared (not iOS-only) so the list renders to
// PNG in the macOS test target; the navigation stays in `RootTabView`.

/// One row of the More sheet.
enum MoreSheetEntry: String, CaseIterable, Identifiable, Hashable {
    case health, stress, breathe, labBook
    case trends
    case alarms, backupSync, dataSources, settings
    // « Advanced », folded.
    case rhythm, explore, compare, insightsHub, intelligence, insights
    case fusedRecord, appleHealth, miBand, shortcutsExport, noopLimitations
    case automations, siriShortcuts, powerSaving, testCentre

    var id: String { rawValue }

    /// The fifteen screens « Advanced » holds, in the mockup's order.
    static let advanced: [MoreSheetEntry] = [
        .rhythm, .explore, .compare, .insightsHub, .intelligence, .insights,
        .fusedRecord, .appleHealth, .miBand, .shortcutsExport, .noopLimitations,
        .automations, .siriShortcuts, .powerSaving, .testCentre,
    ]

    var isAdvanced: Bool { Self.advanced.contains(self) }

    var title: LocalizedStringKey {
        switch self {
        case .health: return "Health"
        case .stress: return "Stress"
        case .breathe: return "Breathe"
        case .labBook: return "Lab Book"
        case .trends: return "Trends"
        case .alarms: return "Alarms"
        case .backupSync: return "Backup"
        case .dataSources: return "Data Sources"
        case .settings: return "Settings"
        case .rhythm: return "Rhythm"
        case .explore: return "Explore"
        case .compare: return "Compare"
        case .insightsHub: return "What Moves You"
        case .intelligence: return "Intelligence"
        case .insights: return "Insights"
        case .fusedRecord: return "Your Data, Fused"
        case .appleHealth: return "Apple Health"
        case .miBand: return "Mi Band"
        case .shortcutsExport: return "Shortcuts Export"
        case .noopLimitations: return "NOOP Limitations"
        case .automations: return "Automations"
        case .siriShortcuts: return "Siri & Shortcuts"
        case .powerSaving: return "Power saving"
        case .testCentre: return "Test Centre"
        }
    }

    /// SF Symbol of the row's tile (the main sections only).
    var icon: String {
        switch self {
        case .health: return "heart.text.square.fill"
        case .stress: return "bolt.heart.fill"
        case .breathe: return "wind"
        case .labBook: return "books.vertical.fill"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .alarms: return "alarm.fill"
        case .backupSync: return "externaldrive.fill.badge.icloud"
        case .dataSources: return "externaldrive.fill"
        case .settings: return "gearshape.fill"
        default: return "chevron.right"
        }
    }

    /// The tile's colour: the colour of the world the row opens (heart rose for health, the stress amber,
    /// HRV cyan for trends, the activity orange for alarms), the utilities grey.
    var tint: Color {
        switch self {
        case .health: return StrandPalette.liquidHeart
        case .stress: return StrandPalette.metricAmber
        case .breathe: return StrandPalette.metricCyan
        case .labBook: return StrandPalette.metricPurple
        case .trends: return StrandPalette.metricCyan
        case .alarms: return StrandPalette.caloriesActivity
        default: return StrandPalette.textTertiary
        }
    }

    /// Where an « Advanced » screen used to live, named on its right.
    var formerGroup: LocalizedStringKey? {
        switch self {
        case .rhythm: return "Health"
        case .explore, .compare, .insightsHub, .intelligence, .insights: return "Analysis"
        case .fusedRecord, .appleHealth, .miBand, .shortcutsExport, .noopLimitations: return "Data"
        case .automations, .siriShortcuts, .powerSaving, .testCentre: return "App settings"
        default: return nil
        }
    }
}

/// The three sections above « Advanced ».
enum MoreSheetSection: CaseIterable, Identifiable {
    case healthRecovery, analysis, dataSettings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .healthRecovery: return "Health & recovery"
        case .analysis: return "Analysis"
        case .dataSettings: return "Data & settings"
        }
    }

    var entries: [MoreSheetEntry] {
        switch self {
        case .healthRecovery: return [.health, .stress, .breathe, .labBook]
        case .analysis: return [.trends]
        case .dataSettings: return [.alarms, .backupSync, .dataSources, .settings]
        }
    }
}

/// The values shown on the right of five rows, already worded; nil = nothing shown.
struct MoreSheetValues: Equatable {
    var vitality: Int?
    var stress: String?
    var labDay: String?
    var alarm: String?
    var backup: String?

    func value(for entry: MoreSheetEntry) -> String? {
        switch entry {
        case .health: return vitality.map { String(localized: "Vitality \($0)") }
        case .stress: return stress
        case .labBook: return labDay
        case .alarms: return alarm
        case .backupSync: return backup
        default: return nil
        }
    }
}

enum MoreSheetReader {
    /// Reads the five values, each from the source of the screen it names: the last Vitality (as Today's
    /// card), today's stress now (Today's stress card, `StressDayCurve` + `TodayStressLogic`), the newest lab
    /// entry, the next alarm the strap will actually ring (`SmartAlarmView.nextArmedStrapAlarm`, the screen's
    /// own funnel) and the last backup (`FolderBackup.lastBackupMs`, as Backup & Sync).
    @MainActor
    static func loadMoreSheetValues(repo: Repository, behavior: BehaviorStore, isWhoop5: Bool,
                                    now: Date = Date()) async -> MoreSheetValues {
        var values = MoreSheetValues()
        if let vitality = await repo.exploreSeries(key: "vitality", source: "my-whoop").last?.value {
            values.vitality = Int(vitality.rounded())
        }
        let dayStart = Calendar.current.startOfDay(for: Repository.logicalDay(now))
        if let scored = await StressDayCurve.day(repo: repo, dayStart: dayStart,
                                                 personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled) {
            let model = TodayStressLogic.model(result: scored.result, dayStart: Int(dayStart.timeIntervalSince1970),
                                               now: Int(now.timeIntervalSince1970), isToday: true)
            if let level = model.latestLevel {
                values.stress = TodayStressLogic.bandName(TodayStressLogic.stressBand(level))
            }
        }
        if let store = await repo.storeHandle() {
            var latest: Int?
            for category in LabMarkerCategory.allCases {
                let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
                for row in rows where row.takenAt > (latest ?? Int.min) { latest = row.takenAt }
            }
            values.labDay = latest.map {
                Date(timeIntervalSince1970: TimeInterval($0)).formatted(.dateTime.day().month(.abbreviated))
            }
        }
        if let next = SmartAlarmView.nextArmedStrapAlarm(enabled: behavior.smartAlarmEnabled,
                                                         minutes: behavior.smartAlarmMinutes,
                                                         weekdays: behavior.smartAlarmWeekdays,
                                                         overrides: WindDownNudge.perDayWakeOverrides,
                                                         isWhoop5: isWhoop5, from: now) {
            values.alarm = moreAlarmText(next, now: now)
        }
        values.backup = moreBackupText(lastMs: FolderBackup.lastBackupMs, now: now)
        return values
    }

    /// The next alarm: its time within a day, else its weekday and time (« 06:04 », « Sat 08:30 »).
    static func moreAlarmText(_ next: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.setLocalizedDateFormatFromTemplate(next.timeIntervalSince(now) < 86_400 ? "jj:mm" : "EEE jj:mm")
        return formatter.string(from: next)
    }

    /// The last backup as a day (« today », « yesterday », « 3 days ago »); nil when none was made.
    static func moreBackupText(lastMs: Int, now: Date, calendar: Calendar = .current) -> String? {
        guard lastMs > 0 else { return nil }
        let last = Date(timeIntervalSince1970: TimeInterval(lastMs) / 1000)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: -max(0, days)))
    }
}

// MARK: - Views

/// The sections, then « Advanced » folded. `row` wraps each label in the caller's navigation link (the
/// sheet's `NavigationPath` values live in `RootTabView`); the render test passes the bare label.
struct MoreSheetList<Row: View>: View {
    let row: (MoreSheetEntry, _ isLast: Bool) -> Row
    @State private var showsAdvanced = false

    // Explicit, since the private state makes the memberwise one private to this file.
    init(@ViewBuilder row: @escaping (MoreSheetEntry, _ isLast: Bool) -> Row) {
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MoreSheetSection.allCases) { section in
                Text(section.title)
                    .font(StrandFont.footnote.weight(.medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.top, 10)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                card(section.entries)
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showsAdvanced.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Advanced")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.accent)
                    Spacer(minLength: 8)
                    Group {
                        if showsAdvanced {
                            Text("Hide")
                        } else {
                            Text("\(MoreSheetEntry.advanced.count) screens")
                        }
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(StrandPalette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityValue(showsAdvanced ? Text("Hide") : Text("\(MoreSheetEntry.advanced.count) screens"))
            if showsAdvanced {
                card(MoreSheetEntry.advanced)
            }
        }
    }

    private func card(_ entries: [MoreSheetEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                row(entry, entry == entries.last)
            }
        }
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
    }
}

/// One row: a coloured tile, the name, the value on the right, a chevron; an « Advanced » row has no tile
/// and names, on its right, the group it used to sit in.
struct MoreSheetRowLabel: View {
    let entry: MoreSheetEntry
    var value: String?
    var showsDivider = true

    var body: some View {
        HStack(spacing: 12) {
            if !entry.isAdvanced {
                Image(systemName: entry.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                    .frame(width: 30, height: 30)
                    .background(entry.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                Text(entry.title)
                    .font(entry.isAdvanced ? StrandFont.subhead : StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let value {
                    Text(verbatim: value)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                } else if let group = entry.formerGroup {
                    Text(group)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 16)
            .frame(minHeight: entry.isAdvanced ? 44 : 48)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(height: NoopMetrics.hairlineWidth)
                }
            }
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The profile card at the head of the sheet: the avatar, the first name the Coach greets with (« Profile
/// and settings » until one is written), the strap line under it, a chevron. A tap opens Settings.
struct MoreProfileCard: View {
    var name: String
    var avatarImageData: Data?
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(imageData: avatarImageData, size: 54)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if name.isEmpty {
                        Text("Profile and settings")
                    } else {
                        Text(verbatim: name)
                    }
                }
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                if let detail {
                    Text(verbatim: detail)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// `MoreProfileCard` fed live: the active device's name (`Repository.activeDeviceDisplayName`), its charge
/// as Today's battery ring resolves it (`LiquidTodayView.StrapBatteryDisplay`) and the last sync. Its own
/// leaf so only it observes `LiveState`.
struct MoreProfileCardHost: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @AppStorage(CoachGreeting.firstNameKey) private var firstName = ""
    var avatarImageData: Data?
    @State private var deviceName: String?

    init(avatarImageData: Data?) {
        self.avatarImageData = avatarImageData
    }

    var body: some View {
        MoreProfileCard(name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatarImageData: avatarImageData, detail: detailLine)
            .task(id: repo.refreshSeq) { deviceName = repo.activeDeviceDisplayName() }
    }

    private var detailLine: String? {
        var parts: [String] = []
        if let deviceName { parts.append(deviceName) }
        let battery = LiquidTodayView.StrapBatteryDisplay.resolve(
            activeIsWhoop: live.activeIsWhoop, connected: live.connected, batteryPct: live.batteryPct,
            charging: live.charging, ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
        if case .charge(let pct, _, _) = battery {
            parts.append((pct / 100).formatted(.percent.precision(.fractionLength(0))))
        }
        if let synced = live.lastSyncedAt, synced > 0 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = AppLanguage.activeLocale
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: Date(timeIntervalSince1970: synced), relativeTo: Date())
            parts.append(String(localized: "synced \(ago)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
