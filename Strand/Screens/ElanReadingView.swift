import SwiftUI
import StrandDesign

// MARK: - Élan · a reading (personal fork, chantier 10, PR B)
//
// One reading, essential (now) or daily (PR D): the theme, the title, the three points of « L'essentiel »,
// the sections with their source numbers, « Pour toi » (the reader's own figures, from the screens that own
// them), « À essayer », the sources as links, and the disclaimer. Opening it marks it read.

struct ElanReadingView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    let reading: ElanReading
    let figures: ElanFigures

    private var language: String { ElanFormat.languageCode }
    private var themeColor: Color { ElanFormat.themeColor(reading.theme) }

    var body: some View {
        ScreenScaffold(title: nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                ElanSectionTitle("The essentials")
                pointsCard
                ForEach(Array(reading.sections.enumerated()), id: \.offset) { index, section in
                    sectionView(section, index: index)
                }
                let rows = figures.rows(for: reading)
                if !rows.isEmpty {
                    ElanSectionTitle("For you")
                    forYouCard(rows)
                }
                tryCard
                ElanSectionTitle("Sources")
                sourcesCard
                Text("A synthesis written from these sources. It is not medical advice.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                ElanActionButton(title: Text("Ask the Coach"), look: .primary, systemImage: "sparkles") {
                    coach.pendingPrompt = String(localized: "Explain to me, from my own data: \(reading.title.text(languageCode: language))")
                    router.openCoach()
                }
            }
        }
        .noopEntranceRoot()
        .onAppear { ElanReadLog.markRead(reading.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: ElanFormat.themeName(reading.theme))
                Text(verbatim: "·")
                Text("essential")
            }
            .font(StrandFont.footnote.weight(.semibold))
            .foregroundStyle(themeColor)
            Text(verbatim: reading.title.text(languageCode: language))
                .font(StrandFont.title1)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(reading.minutes) min · \(reading.sources.count) sources")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var pointsCard: some View {
        NoopCard(padding: 4) {
            VStack(spacing: 0) {
                let points = reading.points.texts(languageCode: language)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: String(index + 1))
                            .font(StrandFont.footnote.weight(.bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(width: 24, height: 24)
                            .background(StrandPalette.surfaceInset, in: Circle())
                        Text(verbatim: point)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if index < points.count - 1 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                .padding(.leading, 48)
                        }
                    }
                    .staggeredAppear(index: index)
                }
            }
        }
    }

    private func sectionView(_ section: ElanReadingSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: section.heading.text(languageCode: language))
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            (Text(verbatim: section.body.text(languageCode: language))
             + Text(verbatim: " ")
             + Text(verbatim: "[\(section.source)]").foregroundColor(StrandPalette.accent))
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .staggeredAppear(index: index + 3)
    }

    private func forYouCard(_ rows: [(key: ElanFigureKey, value: String)]) -> some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(figureName(row.key))
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Text(verbatim: row.value)
                            .font(StrandFont.rounded(16))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) {
                        if index < rows.count - 1 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func figureName(_ key: ElanFigureKey) -> LocalizedStringKey {
        switch key {
        case .hrvLastNight: return "HRV, last night"
        case .hrvNormal: return "Your normal HRV"
        case .restingHrLastNight: return "Resting heart rate, last night"
        case .restingHrNormal: return "Your normal resting heart rate"
        case .spo2LastNight: return "Blood oxygen, last night"
        case .respiratoryRateLastNight: return "Respiratory rate, last night"
        case .sleepLastNight: return "Sleep, last night"
        case .sleepNeed: return "Your sleep need"
        case .sleepDebt: return "Sleep debt"
        case .sleepAverage7: return "Nights, 7-day average"
        case .chargeToday: return "Charge today"
        case .effortToday: return "Effort today"
        case .proteinGoal: return "Protein goal"
        case .intakeGoal: return "Intake goal"
        case .intakeToday: return "Eaten today"
        case .sessionsThisWeek: return "Sessions this week"
        }
    }

    private var tryCard: some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                ElanSandLabel(text: Text("To try"))
                Text(verbatim: reading.tryIt.text(languageCode: language))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourcesCard: some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(reading.sources.enumerated()), id: \.offset) { index, source in
                    Group {
                        if let url = URL(string: source.url) {
                            Link(destination: url) { sourceRow(source, index: index) }
                        } else {
                            sourceRow(source, index: index)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if index < reading.sources.count - 1 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func sourceRow(_ source: ElanReadingSource, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "[\(index + 1)]")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: source.title)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: source.year.map { "\(source.host) · \($0)" } ?? source.host)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
