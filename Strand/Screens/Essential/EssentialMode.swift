import SwiftUI
import StrandDesign

// MARK: - Essential mode (personal fork, chantier 20)
//
// One switch, the ◎ button at the top right of each tab root, keeps only the day's figures on Today,
// Sleep, Nutrition, Training and Coach: the rings in the middle with their animation, a few numbers and
// one action per screen. Nothing is stored beyond the switch, and nothing is computed anew: each screen
// draws its essential layout from the model it already built for its full layout.
// Mockup: https://claude.ai/artifact/KfSKyyoxDCbJJD4rxMixBK

/// Where the switch lives. A viewing preference of this phone: kept on the device, outside `.noopbak`.
enum EssentialMode {
    static let storageKey = "noop.essentialMode"
}

/// The ◎ button beside the profile picture: grey glass when the mode is off, white when it is on. It renders
/// nothing outside the iOS tab shell, like `MoreAvatarButton`, so macOS and the render tests are unchanged.
struct EssentialModeButton: View {
    @Environment(\.showsMoreAvatar) var shows
    @AppStorage(EssentialMode.storageKey) var on = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var motion = NoopMotionState.shared

    var body: some View {
        if shows {
            button
        }
    }

    @ViewBuilder private var button: some View {
        let toggle = Button {
            StrandHaptic.selection.play()
            withAnimation(NoopMotion.gated(NoopMotion.card, reduced: motion.poseStill(reduceMotion))) { on.toggle() }
        } label: {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .background(on ? StrandPalette.textPrimary : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(Text("Essential mode"))
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityHint(on ? Text("Shows the whole screen again") : Text("Keeps only your figures"))
        if on {
            toggle.buttonStyle(LiquidPressStyle())
        } else {
            toggle.nativeLiquidGlassHeaderButton()
        }
    }
}

/// The top line of an essential screen: a grey caption on the left (the day, the night, the week), then the
/// ◎ button and the profile picture.
struct EssentialHeader: View {
    let caption: String

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: caption)
                .font(StrandFont.overline)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            EssentialModeButton()
            MoreAvatarButton()
        }
        .frame(minHeight: 44)
    }
}

/// One figure under an essential ring: the coloured name, then the number, then a grey unit. A button
/// when `onTap` is set (Today: it lights its ring alone).
struct EssentialFigure: View {
    let label: String
    let tint: Color
    let value: String
    var unit: String? = nil
    var selected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(LiquidPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 1) {
            Text(verbatim: label)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(verbatim: value)
                .font(StrandFont.number(20, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(verbatim: unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.vertical, 6)
        .background(selected ? StrandPalette.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The white capsule of an essential screen's one action (Add a meal, Start, Today's brief).
struct EssentialActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var symbolTint: Color = StrandPalette.surfaceBase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolTint)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(StrandPalette.surfaceBase)
            }
            .font(StrandFont.headline)
            .padding(.horizontal, 28)
            .frame(minHeight: NoopButtonMetrics.height)
            .background(StrandPalette.textPrimary, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(LiquidPressStyle())
    }
}
