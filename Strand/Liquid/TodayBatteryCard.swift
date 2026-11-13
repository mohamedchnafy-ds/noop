import SwiftUI
import StrandDesign
import StrandAnalytics

// Personal fork (Démarrer tools, 12 Nov.): the strap's battery, readable at a glance on Today, right under
// the title. The header's small ring only drew a level; this card states the percentage, the runtime left
// and the charging state in words. Both resolve from ONE funnel, `LiquidTodayView.StrapBatteryDisplay`, so
// they can never disagree (two readouts of one fact, AGENTS.md): no stale percentage once the link is down,
// and a ring's own charge under an active ring.

/// What the card says, from the battery display and the runtime estimate. Pure, so it is testable.
struct TodayBatteryLine: Equatable {
    enum Level: Equatable { case good, low, critical, charging, unknown }

    let title: String
    /// The big figure: « 73 % », or nil when there is no honest reading.
    let value: String?
    let detail: String?
    let level: Level
    /// 0...1 for the battery glyph, nil with no reading.
    let fraction: Double?

    /// Same thresholds as the Live screen's battery tint: 15 % and 30 %.
    static let lowPercent = 30.0
    static let criticalPercent = 15.0

    static func todayBatteryLine(_ display: LiquidTodayView.StrapBatteryDisplay,
                                 estimate: String?) -> TodayBatteryLine? {
        switch display {
        case .notActiveDevice:
            return nil
        case .offline:
            return TodayBatteryLine(title: String(localized: "Strap battery"), value: nil,
                                    detail: String(localized: "Strap not connected"), level: .unknown,
                                    fraction: nil)
        case .pending(let charging):
            return TodayBatteryLine(title: String(localized: "Strap battery"), value: nil,
                                    detail: charging ? String(localized: "Charging")
                                                     : String(localized: "Waiting for the strap's reading"),
                                    level: charging ? .charging : .unknown, fraction: nil)
        case .charge(let pct, let charging, let isRing):
            let clamped = max(0, min(100, pct))
            let level: Level = charging ? .charging
                : clamped <= criticalPercent ? .critical
                : clamped <= lowPercent ? .low : .good
            let detail: String?
            if charging {
                detail = String(localized: "Charging")
            } else if clamped <= criticalPercent {
                detail = [String(localized: "Charge it soon"), estimate].compactMap { $0 }.joined(separator: " · ")
            } else {
                detail = estimate
            }
            return TodayBatteryLine(
                title: isRing ? String(localized: "Ring battery") : String(localized: "Strap battery"),
                value: StrapLogReader.strapLogPercent(Int(clamped.rounded())),
                detail: detail, level: level, fraction: clamped / 100)
        }
    }

    /// « ~5 days left » / « ~20 h left », from the strap's banked discharge (#992). nil while charging or
    /// with no estimate yet, so the card only states a runtime the app trusts. Same rule as the Data
    /// Sources row.
    static func todayBatteryEstimate(charging: Bool?, estimate: BatteryEstimator.Estimate?) -> String? {
        guard charging != true, let estimate else { return nil }
        let hours = estimate.hoursRemaining
        guard hours.isFinite, hours > 0 else { return nil }
        if hours < 48 { return String(localized: "~\(Int(hours.rounded()))h left") }
        let days = Int((hours / 24).rounded())
        return days == 1 ? String(localized: "~1 day left") : String(localized: "~\(days) days left")
    }
}

/// The card itself. Tap → Devices, like the header's ring.
struct TodayBatteryCard: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter

    private var line: TodayBatteryLine? {
        let display = LiquidTodayView.StrapBatteryDisplay.resolve(
            activeIsWhoop: live.activeIsWhoop,
            connected: live.connected,
            batteryPct: live.batteryPct,
            charging: live.charging,
            ringPct: live.ouraBatteryPct,
            ringCharging: live.ouraWearState == .charging
        )
        // The runtime estimate is the strap's: never beside a ring's charge.
        let isStrap: Bool
        if case .charge(_, _, let isRing) = display { isStrap = !isRing } else { isStrap = true }
        let estimate = isStrap ? TodayBatteryLine.todayBatteryEstimate(charging: live.charging,
                                                                      estimate: live.batteryEstimate) : nil
        return TodayBatteryLine.todayBatteryLine(display, estimate: estimate)
    }

    var body: some View {
        if let line {
            Button { router.openDevices() } label: { content(line) }
                .buttonStyle(LiquidPressStyle())
                .accessibilityElement(children: .combine)
        }
    }

    private func content(_ line: TodayBatteryLine) -> some View {
        let tint = Self.tint(line.level)
        return HStack(spacing: 14) {
            Image(systemName: Self.symbol(line))
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let detail = line.detail {
                    Text(detail)
                        .font(StrandFont.footnote)
                        .foregroundStyle(line.level == .critical ? tint : StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value = line.value {
                Text(value)
                    .font(StrandFont.rounded(30, weight: .bold))
                    .foregroundStyle(line.level == .good ? StrandPalette.textPrimary : tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface())
        .contentShape(Rectangle())
    }

    static func tint(_ level: TodayBatteryLine.Level) -> Color {
        switch level {
        case .good: return StrandPalette.statusPositive
        case .low: return StrandPalette.statusWarning
        case .critical: return StrandPalette.statusCritical
        case .charging: return StrandPalette.accent
        case .unknown: return StrandPalette.textTertiary
        }
    }

    /// The battery glyph at the nearest quarter, with a bolt while charging.
    static func symbol(_ line: TodayBatteryLine) -> String {
        if line.level == .charging { return "battery.100percent.bolt" }
        guard let f = line.fraction else { return "battery.0percent" }
        switch f {
        case ..<0.125: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
