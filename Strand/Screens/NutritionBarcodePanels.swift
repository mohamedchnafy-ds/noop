import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork, Nutrition 4d (mockups 7 and 9): the panel under the barcode scanner's camera. Pure
// views, so the PNG render draws them without a camera; the scanner itself is iOS only
// (`NutritionBarcodeScanner.swift`).

/// The rounded panel each state of the scanner sits in.
struct BarcodePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, NoopMetrics.space2)
                .accessibilityHidden(true)
            content
                .padding(.top, NoopMetrics.space3)
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.bottom, NoopMetrics.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised,
                    in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
    }
}

/// While the camera looks for a barcode, and while Open Food Facts is asked for one (`searching`).
struct BarcodeLookingPanel: View {
    var searching = false
    let onManual: () -> Void

    var body: some View {
        BarcodePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                (searching ? Text("Searching Open Food Facts…") : Text("Point the camera at the barcode"))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                (searching
                    ? Text("Only the barcode is sent. A product you have already added is recognised on your iPhone, without a network.")
                    : Text("A product you have already added is recognised on your iPhone, without a network."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                NoopButton("Enter by hand", kind: .secondary, fullWidth: true, action: onManual)
            }
        }
    }
}

/// Mockup 7: a barcode the journal has never seen.
struct BarcodeUnknownPanel: View {
    let barcode: String
    /// The Coach is on, connected, and reads photos (Anthropic).
    let canReadLabel: Bool
    /// What Open Food Facts said, when it was asked: not found, or not reachable.
    var miss: OpenFoodFacts.Lookup? = nil
    let onPhoto: () -> Void
    let onManual: () -> Void

    var body: some View {
        BarcodePanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: NoopMetrics.space3) {
                    Image(systemName: "barcode")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(StrandPalette.surfaceOverlay,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not in your journal yet")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: NutritionFormat.barcodeLine(barcode))
                            .font(StrandFont.footnote.monospacedDigit())
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if let missText {
                    missText
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopMetrics.space3)
                }
                Group {
                    if canReadLabel {
                        Text("Photograph the nutrition table on the label: the Coach reads it, you check before adding. Next time, this product is recognised without a network.")
                    } else {
                        Text("Labels are read by the Coach with Anthropic. Turn it on in Coach settings, or enter the product by hand.")
                    }
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.space4)
                if canReadLabel {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        barcodeNote(symbol: "arrow.up.forward",
                                    text: "Sent with your Anthropic key: the photo of the label and the barcode, nothing else.")
                        barcodeNote(symbol: "iphone",
                                    text: "Kept on your iPhone: the name and the values for 100 g, with the meal you add.")
                    }
                    .padding(NoopMetrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    .padding(.top, NoopMetrics.space4)
                }
                VStack(spacing: NoopMetrics.space2) {
                    if canReadLabel {
                        NoopButton("Photograph the label", systemImage: "camera", kind: .primary, fullWidth: true,
                                   action: onPhoto)
                    }
                    NoopButton("Enter by hand", kind: .secondary, fullWidth: true, action: onManual)
                }
                .padding(.top, NoopMetrics.space5)
            }
        }
    }

    /// One line on why Open Food Facts did not give the product.
    private var missText: Text? {
        switch miss {
        case .notFound?: return Text("Open Food Facts does not have this product (or not its values for 100 g).")
        case .unreachable?: return Text("Open Food Facts could not be reached (no network?).")
        case .found?, nil: return nil
        }
    }

    private func barcodeNote(symbol: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
            Image(systemName: symbol)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Mockup 9: a product the journal already holds, read on the iPhone.
struct BarcodeKnownPanel: View {
    let product: BarcodeProduct
    @Binding var grams: Double
    let saving: Bool
    /// Nil when the Coach cannot read a label (no "Read the label again").
    let onReread: (() -> Void)?
    let onAdd: () -> Void

    var body: some View {
        let portion = MealMath.portion(per100: product.per100, grams: grams)
        BarcodePanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: product.name)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        (product.source == .openFoodFacts
                            ? Text("Open Food Facts (ODbL) · check the values before adding")
                            : Text("already in your journal · on your iPhone"))
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let onReread {
                        Button(action: onReread) {
                            product.source == .openFoodFacts ? Text("Read the label") : Text("Read the label again")
                        }
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.accent)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                }
                HStack(spacing: NoopMetrics.space2) {
                    Text("Per 100 g")
                        .font(StrandFont.overlineScaled(11))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: NutritionFormat.per100Line(product.per100))
                        .font(StrandFont.footnote.monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, NoopMetrics.space2)
                portionStepper
                    .padding(.top, NoopMetrics.space4)
                portionChips
                    .padding(.top, NoopMetrics.space2)
                MealTotalsRow(total: portion)
                    .padding(.horizontal, NoopMetrics.space3)
                    .padding(.vertical, 10)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    .padding(.top, NoopMetrics.space3)
                Text(verbatim: product.source == .openFoodFacts ? NutritionFormat.portionRatio(grams)
                                                                : NutritionFormat.portionFormula(grams))
                    .font(StrandFont.caption.monospacedDigit())
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.top, NoopMetrics.space1)
                NoopButton("Add to journal", systemImage: "plus", kind: .primary, fullWidth: true, action: onAdd)
                    .disabled(saving)
                    .padding(.top, NoopMetrics.space5)
            }
        }
    }

    private var portionStepper: some View {
        HStack {
            Text("Portion")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            HStack(spacing: NoopMetrics.space1) {
                portionStepButton(symbol: "minus", label: "Less", delta: -BarcodeCatalog.portionStep)
                Text(verbatim: NutritionFormat.portionGrams(grams, estimated: false))
                    .font(StrandFont.headline.monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 70)
                portionStepButton(symbol: "plus", label: "More", delta: BarcodeCatalog.portionStep)
            }
        }
    }

    private func portionStepButton(symbol: String, label: LocalizedStringKey, delta: Double) -> some View {
        Button {
            grams = MealJournal.clampedPortion(grams + delta)
        } label: {
            Image(systemName: symbol)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(StrandPalette.surfaceOverlay, in: Circle())
                .overlay(Circle().strokeBorder(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var portionChips: some View {
        HStack(spacing: NoopMetrics.space2) {
            ForEach(BarcodeCatalog.portionChoices(lastGrams: product.lastGrams), id: \.self) { choice in
                let selected = MealMath.tenth(grams) == choice
                Button {
                    grams = choice
                } label: {
                    Text(verbatim: chipText(choice))
                        .font(StrandFont.subhead.weight(selected ? .semibold : .regular))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(selected ? StrandPalette.surfaceOverlay : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? StrandPalette.accent : StrandPalette.hairlineStrong,
                                                        lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// "150 g · last time" for last time's quantity, "100 g" otherwise.
    private func chipText(_ choice: Double) -> String {
        let text = NutritionFormat.portionGrams(choice, estimated: false)
        guard let last = product.lastGrams, MealJournal.clampedPortion(last) == choice else { return text }
        return text + " · " + String(localized: "last time")
    }
}
