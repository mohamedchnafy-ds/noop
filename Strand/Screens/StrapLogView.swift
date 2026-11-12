import SwiftUI
import StrandDesign
import StrandAnalytics

// Personal fork (Démarrer tools, 12 Nov., mockup https://claude.ai/artifact/5eDS6cxaaXBT3FQ6UdQf4K, boards 1
// and 5): the strap log in plain words. Each recognised line is a sentence (`StrapLogReader`), newest first,
// with filter chips by topic; the raw lines stay behind the « Technical lines » switch, off by default. Copy
// and Save export the raw buffer exactly as before, for a bug report.

/// Reads the log tail once per published revision, however often the view re-evaluates in between.
final class StrapLogReadingCache {
    private var revision: UInt64?
    private var tailLines = 0
    private var reading = StrapLogReading(entries: [], technicalLines: 0)

    /// `revision` is `LiveState.logRevision`, which ticks once per coalesced publish of `log`.
    func strapLogReading(log: [String], revision: UInt64, tailLines: Int) -> StrapLogReading {
        if self.revision == revision, self.tailLines == tailLines { return reading }
        reading = StrapLogReader.readStrapLog(LiveState.renderedTail(log, tailLines: tailLines))
        self.revision = revision
        self.tailLines = tailLines
        return reading
    }
}

/// The link's state in one line, resolved from the live state the same way wherever it is shown.
struct StrapLinkSummaryRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        let summary = Self.currentSummary(model: model, live: live)
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Self.tint(summary.level))
                .frame(width: 11, height: 11)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = summary.detail {
                    Text(detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    static func tint(_ level: StrapLinkSummary.Level) -> Color {
        switch level {
        case .good: return StrandPalette.statusPositive
        case .warning: return StrandPalette.statusWarning
        case .off: return StrandPalette.textTertiary
        }
    }

    /// The summary of the ACTIVE device, with the readouts the Live screen uses for it.
    static func currentSummary(model: AppModel, live: LiveState) -> StrapLinkSummary {
        let devices = model.deviceRegistry?.devices ?? []
        let activeId = model.deviceRegistry?.activeDeviceId
        let isWhoop = LiveConsoleReadout.activeIsWhoop(devices: devices, activeId: activeId)
        let name = devices.first(where: { $0.id == activeId })?.displayName ?? "WHOOP"
        let ringStreaming = live.connected && live.streamingLiveHR
        let trusted = (isWhoop && live.bonded) || ringStreaming
        let battery = LiveConsoleReadout.batteryPercent(activeIsWhoop: isWhoop, whoopPct: live.batteryPct,
                                                        ringPct: live.ouraBatteryPct)
        let lastSync = live.lastSyncedAt.map { ts -> String in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
        }
        return StrapLinkSummary.strapLinkSummary(
            deviceName: name, connected: live.connected, trusted: trusted,
            liveHeartRateOnly: isWhoop && live.bonded && !live.encryptedBond,
            liveHeartRate: live.connected && model.bpm != nil, syncing: live.backfilling,
            batteryPercent: live.connected ? battery : nil, lastSyncLabel: lastSync)
    }
}

/// One sentence of the plain log, with its raw lines under it when asked.
struct StrapLogEntryRow: View {
    let entry: StrapLogEntry
    var showsRaw = false
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !compact { icon }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(compact ? StrandFont.subhead : StrandFont.body)
                        .foregroundStyle(entry.phrase?.topic == .problem ? StrandPalette.statusWarning
                                         : entry.phrase == nil ? StrandPalette.textSecondary
                                         : StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let clock = entry.clock {
                        Text(verbatim: clock)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if !compact, let detail {
                    Text(detail)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsRaw {
                    Text(verbatim: rawText)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(StrandPalette.surfaceInset,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, compact ? 9 : 10)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let phrase = entry.phrase { return phrase.title }
        return entry.lineCount == 1 ? String(localized: "1 technical line")
            : String(localized: "\(entry.lineCount) technical lines")
    }

    /// The sentence's detail, plus « ×14 since 19:33 » when lines folded into it.
    private var detail: String? {
        var parts: [String] = []
        if let detail = entry.phrase?.detail { parts.append(detail) }
        if entry.phrase != nil, entry.repeats > 1 {
            if let first = entry.firstClock, first != entry.clock {
                parts.append(String(localized: "×\(entry.repeats) since \(first)"))
            } else {
                parts.append("×\(entry.repeats)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var rawText: String {
        let hidden = entry.lineCount - entry.rawLines.count
        let lines = entry.rawLines.joined(separator: "\n")
        return hidden > 0 ? String(localized: "… \(hidden) earlier lines") + "\n" + lines : lines
    }

    private var icon: some View {
        let topic = entry.phrase?.topic
        let tint = Self.tint(topic)
        return Image(systemName: Self.symbol(topic))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }

    static func symbol(_ topic: StrapLogTopic?) -> String {
        switch topic {
        case .connection: return "link"
        case .heartRate: return "heart.fill"
        case .history: return "arrow.triangle.2.circlepath"
        case .battery: return "battery.75percent"
        case .other: return "arrow.right"
        case .problem: return "exclamationmark.triangle.fill"
        case nil: return "chevron.left.forwardslash.chevron.right"
        }
    }

    static func tint(_ topic: StrapLogTopic?) -> Color {
        switch topic {
        case .connection: return StrandPalette.accent
        case .heartRate: return StrandPalette.liquidHeart
        case .history: return StrandPalette.metricCyan
        case .battery: return StrandPalette.statusPositive
        case .other, nil: return StrandPalette.textSecondary
        case .problem: return StrandPalette.statusWarning
        }
    }
}

/// The Live screen's short version: the last few sentences, and « See all » to the full screen.
struct StrapLogRecentCard: View {
    private static let tailLines = 300
    private static let shownEntries = 4

    @EnvironmentObject private var live: LiveState
    @Environment(\.scenePhase) private var scenePhase
    @State private var cache = StrapLogReadingCache()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What the strap is doing")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                NavigationLink(destination: StrapLogView()) {
                    Text("See all")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            // Backgrounded, nothing is on screen to keep current (#2521): no reading at all.
            if scenePhase != .background {
                let rows = cache.strapLogReading(log: live.log, revision: live.logRevision, tailLines: Self.tailLines)
                    .strapLogRows(topic: nil, technical: false)
                    .prefix(Self.shownEntries)
                if rows.isEmpty {
                    Text("Nothing yet: the strap's events appear here as they happen.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(rows)) { entry in
                        Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                        StrapLogEntryRow(entry: entry, compact: true)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }
}

/// The full plain log: state, filters, sentences newest first, and the bug-report tools.
struct StrapLogView: View {
    /// How many trailing lines the screen reads. The buffer stays 5,000 lines, and Copy / Save export all.
    private static let tailLines = 1_500

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.scenePhase) private var scenePhase
    @State private var cache = StrapLogReadingCache()
    @State private var topic: StrapLogTopic?
    @State private var showsTechnical = false

    var body: some View {
        ScreenScaffold(title: "Strap log", subtitle: "What the strap and the app tell each other, in plain words.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                StrapLinkSummaryRow()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface())
                filterChips
                entriesCard
                reportCard
            }
        }
    }

    private var reading: StrapLogReading {
        scenePhase == .background ? StrapLogReading(entries: [], technicalLines: 0)
            : cache.strapLogReading(log: live.log, revision: live.logRevision, tailLines: Self.tailLines)
    }

    private static let chipTopics: [StrapLogTopic?] = [nil, .connection, .heartRate, .history, .battery, .problem]

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.chipTopics, id: \.self) { option in
                    Button { topic = option } label: {
                        chipLabel(option)
                            .font(StrandFont.subhead.weight(option == topic ? .semibold : .regular))
                            .foregroundStyle(option == topic ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(option == topic ? StrandPalette.textPrimary
                                                                        : StrandPalette.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == topic ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func chipLabel(_ option: StrapLogTopic?) -> some View {
        switch option {
        case nil: Text("All")
        case .connection: Text("Connection")
        case .heartRate: Text("Heart rate")
        case .history: Text("History")
        case .battery: Text("Battery")
        case .problem: Text("Problems")
        case .other: Text("Other")
        }
    }

    private var entriesCard: some View {
        let current = reading
        let rows = current.strapLogRows(topic: topic, technical: showsTechnical)
        return VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Group {
                    if topic == nil {
                        Text("Nothing yet: the strap's events appear here as they happen.")
                    } else {
                        Text("Nothing of this kind in the recent log.")
                    }
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.vertical, 14)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 0.5) }
                        StrapLogEntryRow(entry: entry, showsRaw: showsTechnical)
                    }
                }
            }
            if !showsTechnical, topic == nil, current.technicalLines > 0 {
                Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                Text("+ \(current.technicalLines) technical lines without a sentence (shown with « Technical lines »)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Report a problem").strandOverline()
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $showsTechnical) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Technical lines")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Shows the raw line under each sentence")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .tint(StrandPalette.switchOn)
                .padding(.vertical, 12)
                Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                Button { PlatformPasteboard.copy(live.exportableLogText()) } label: {
                    Text("Copy the full log").font(StrandFont.body).foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                Button { saveStrapLog() } label: {
                    Text("Save to a file…").font(StrandFont.body).foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                NavigationLink(destination: TestCentreView()) {
                    HStack {
                        Text("Test Centre").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .background(NoopPanelSurface())
            Text("What you copy or save keeps every technical line as it is: that is what a bug report needs.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// Same export as the former log card and Settings (#507): the dynamic « Strap & data » lines included.
    private func saveStrapLog() {
        Task {
            let extra = await DebugDataDiagnostics.dynamicLines(repo: model.repo)
            FileExport.exportText(live.exportableLogText(extraHeaderLines: extra),
                                  suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
        }
    }
}
