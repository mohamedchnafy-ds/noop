import SwiftUI
import StrandDesign

/// A hand-sized bar trend under a hero bubble (personal fork): one bar per day of `HeroInsight.windowDays`,
/// oldest first, the day shown drawn solid and the past at a lighter weight. A nil slot is a day nothing
/// was recorded; it draws as a faint stub at the baseline so the gap stays visible without reading as zero.
///
/// A plain Canvas with no clock: the bars cannot change between data loads, so there is nothing to animate.
struct LiquidMiniBars: View {
    let values: [Double?]
    /// The scale the values sit on (100 for Charge / Rest, the chosen Effort max), so a 60 fills 60 %.
    let maxValue: Double
    let tint: Color
    var width: CGFloat = 44
    var height: CGFloat = 12

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, values.count)
            let gap: CGFloat = 2
            let barWidth = max(1, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            for (i, slot) in values.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)
                let isCurrent = i == values.count - 1
                if let v = slot {
                    let frac = max(0, min(1, v / max(1, maxValue)))
                    let h = max(1.5, CGFloat(frac) * size.height)
                    let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(tint.opacity(isCurrent ? 1 : 0.42)))
                } else {
                    let rect = CGRect(x: x, y: size.height - 1.5, width: barWidth, height: 1.5)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(tint.opacity(0.18)))
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
