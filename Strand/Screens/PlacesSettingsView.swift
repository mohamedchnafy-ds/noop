import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork, chantier 14 step 2: « Lieux » (the switch, the permission, what is kept) and « Suivi de
// position » (how often a point is kept). Mockup v1 screens 5 and 6. The tracker itself is `PlaceTracker`.

/// A settings row's look: a label on the left, a value or a control on the right.
private struct PlacesRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
    }
}

/// The days choice of the « Garder » rows: 3 months, 6 months, 1 year, 2 years.
enum PlaceKeepChoice {
    static func keepLabel(_ days: Int) -> String {
        switch days {
        case 90: return String(localized: "3 months")
        case 180: return String(localized: "6 months")
        case 730: return String(localized: "2 years")
        default: return String(localized: "1 year")
        }
    }
}

/// A grouped card: rows separated by hairlines.
private struct PlacesCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(NoopPanelSurface(cornerRadius: 26))
    }
}

private struct PlacesDivider: View {
    var body: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
    }
}

// MARK: - Lieux

struct PlacesSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var tracker = PlaceTracker.shared
    @AppStorage(PlaceTrackingSettings.enabledKey) private var enabled = false
    @AppStorage(PlaceTrackingSettings.coachReadsKey) private var coachReads = false
    @AppStorage(PlaceTrackingSettings.keepVisitsDaysKey) private var keepVisitsDays = PlaceTrackingSettings.defaultKeepDays
    @AppStorage(PlaceTrackingSettings.modeKey) private var modeRaw = PlaceTrackingSettings.defaultMode.rawValue
    @AppStorage(PlaceTrackingSettings.intervalKey) private var interval = PlaceTrackingSettings.defaultInterval
    @AppStorage(PlaceTrackingSettings.distanceKey) private var distance = PlaceTrackingSettings.defaultDistance
    @AppStorage(PlaceLog.revisionKey) private var revision = 0
    @State private var placeCount = 0
    @State private var confirmErase = false

    var body: some View {
        ScreenScaffold(title: "Places") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if !enabled { introCard }
                if enabled {
                    permissionNotice
                    settingsCard
                    Button(role: .destructive) { confirmErase = true } label: {
                        Text("Erase all places")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(NoopPanelSurface(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                Text("The first differences show after about two weeks. GPS workouts do not depend on this setting. Places and points are part of the .noopbak backup.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Erase all places?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) {
                Task {
                    guard let store = await repo.storeHandle() else { return }
                    await PlaceLog.eraseAllPlaces(store)
                }
            }
        } message: {
            Text("The places and their visits are deleted from this iPhone. The points stay.")
        }
        .task(id: revision) {
            guard let store = await repo.storeHandle() else { return }
            placeCount = await PlaceLog.places(store).count
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(StrandPalette.metricCyan)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.surfaceOverlay))
                .accessibilityHidden(true)
            Text("See your metrics by place")
                .font(StrandFont.sectionTitle)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("The iPhone spots the places where you stay a while (home, work, gym…). NOOP files your heart rate and your stress there, and the HRV and recovery of the nights spent there.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                introLine("Kept: the place (a zone of about 150 m), the time you arrive and leave.")
                introLine("A point every 15 min by default (set in Location tracking).")
                introLine("Everything stays on the iPhone. The Coach reads it only if you allow it.")
            }
            Button {
                enabled = true
                tracker.requestAlwaysPermission()
                tracker.applyPlaceSettings()
            } label: {
                Text("Turn on Places")
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.textPrimary))
            }
            .buttonStyle(.plain)
            Text("iOS will ask for the location « Always ». Without it, the map keeps only the workouts.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private func introLine(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(StrandPalette.statusPositive)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What iOS allows, when it is not « Always ».
    @ViewBuilder
    private var permissionNotice: some View {
        switch tracker.permission {
        case .always:
            EmptyView()
        case .whileUsing:
            notice("Location is allowed « While using » only: places are kept while NOOP is open. Choose « Always » in the Settings app.")
        case .notAsked:
            notice("Location is not allowed yet.")
        case .denied:
            notice("Location is off for NOOP: allow it « Always » in the Settings app.")
        case .unavailable:
            notice("Location tracking is not available on this device.")
        }
    }

    private func notice(_ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.deviationOrange)
                .fixedSize(horizontal: false, vertical: true)
            #if os(iOS)
            if tracker.permission == .notAsked {
                Button("Allow location") { tracker.requestAlwaysPermission() }
                    .font(StrandFont.subhead.weight(.semibold))
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(StrandFont.subhead.weight(.semibold))
            }
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 26))
    }

    private var trackingSummary: String {
        PlaceTrackingSettings.summaryLabel(mode: PlaceTrackingMode(rawValue: modeRaw) ?? .balanced,
                                           intervalMinutes: interval, distanceMeters: distance)
    }

    private var settingsCard: some View {
        PlacesCard {
            PlacesRow(title: "Track my places") {
                Toggle("Track my places", isOn: Binding(get: { enabled }, set: { on in
                    enabled = on
                    tracker.applyPlaceSettings()
                }))
                .labelsHidden()
                .tint(StrandPalette.switchOn)
            }
            PlacesDivider()
            NavigationLink {
                LocationTrackingSettingsView()
            } label: {
                PlacesRow(title: "Location tracking") {
                    Text(verbatim: trackingSummary + " ›")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .buttonStyle(.plain)
            PlacesDivider()
            PlacesRow(title: "The Coach can read it") {
                Toggle("The Coach can read it", isOn: $coachReads)
                    .labelsHidden()
                    .tint(StrandPalette.switchOn)
            }
            PlacesDivider()
            PlacesRow(title: "Keep the visits") {
                Menu {
                    ForEach(PlaceTrackingSettings.keepChoices, id: \.self) { days in
                        Button(PlaceKeepChoice.keepLabel(days)) {
                            keepVisitsDays = days
                            PlaceTracker.shared.applyRetentionNow()
                        }
                    }
                } label: {
                    Text(verbatim: PlaceKeepChoice.keepLabel(keepVisitsDays) + " ›")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            PlacesDivider()
            NavigationLink {
                KnownPlacesView()
            } label: {
                PlacesRow(title: "Known places") {
                    Text(verbatim: String(placeCount) + " ›")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
