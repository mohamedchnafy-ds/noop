import SwiftUI
import StrandDesign
import WhoopStore

// Personal fork, chantier 14 step 2: « Suivi de position » (mockup v1 screen 6), the quiet spans and the
// list of known places.

struct LocationTrackingSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PlaceTrackingSettings.modeKey) private var modeRaw = PlaceTrackingSettings.defaultMode.rawValue
    @AppStorage(PlaceTrackingSettings.intervalKey) private var interval = PlaceTrackingSettings.defaultInterval
    @AppStorage(PlaceTrackingSettings.distanceKey) private var distance = PlaceTrackingSettings.defaultDistance
    @AppStorage(PlaceTrackingSettings.pauseWhenStillKey) private var pauseWhenStill = true
    @AppStorage(PlaceTrackingSettings.quietNightKey) private var quietNight = true
    @AppStorage(PlaceTrackingSettings.quietRangesKey) private var quietRangesData = Data()
    @AppStorage(PlaceTrackingSettings.keepPointsDaysKey) private var keepPointsDays = PlaceTrackingSettings.defaultKeepDays
    @AppStorage(PlaceLog.revisionKey) private var revision = 0
    @State private var lastPointAt: Date?
    @State private var weekCount = 0
    @State private var confirmErase = false

    private var mode: PlaceTrackingMode { PlaceTrackingMode(rawValue: modeRaw) ?? .balanced }

    var body: some View {
        ScreenScaffold(title: "Location tracking") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                modeSection
                if mode != .eco { frequencySection }
                whenSection
                dataSection
                Button(role: .destructive) { confirmErase = true } label: {
                    Text("Erase all points")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.statusCritical)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(NoopPanelSurface(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                Text("iOS shows the location arrow while the tracking runs. If you close NOOP with a swipe, the tracking resumes at the next large move.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Erase all points?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) {
                Task {
                    guard let store = await repo.storeHandle() else { return }
                    await PlaceLog.erasePoints(store)
                }
            }
        } message: {
            Text("The points are deleted from this iPhone. The places and their visits stay.")
        }
        .task(id: revision) { await reloadTracking() }
    }

    private func reloadTracking() async {
        guard let store = await repo.storeHandle() else { return }
        lastPointAt = await PlaceLog.lastPoint(store).map { Date(timeIntervalSince1970: Double($0.ts) / 1000) }
        weekCount = await PlaceLog.pointCount(store, since: Date().addingTimeInterval(-7 * 86_400))
    }

    private var subtitle: String? {
        guard let lastPointAt else { return nil }
        let ago = PlaceTrackingSettings.agoLabel(from: lastPointAt, to: Date())
        return String(localized: "Last point \(ago)") + " · " + String(localized: "\(weekCount) points this week")
    }

    private func apply() { PlaceTracker.shared.applyPlaceSettings() }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode").strandOverline()
            Picker("Mode", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue; apply() })) {
                Text("Saver").tag(PlaceTrackingMode.eco)
                Text("Balanced").tag(PlaceTrackingMode.balanced)
                Text("Precise").tag(PlaceTrackingMode.precise)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 10) {
                modeText
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(1...3, id: \.self) { level in
                            Capsule()
                                .fill(batteryColor(level))
                                .frame(width: 14, height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                    batteryText
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: 26))
        }
    }

    @ViewBuilder
    private var modeText: some View {
        Group {
            switch mode {
            case .eco:
                Text("A point when you move about 500 m (cell network, no GPS). Precise to a neighbourhood: enough for Places, not for a street.")
            case .balanced:
                Text("A point per interval, to about 100 m. Enough to colour the map by heart rate and by stress, hour by hour.")
            case .precise:
                Text("A point every N metres, by GPS. A detailed map, street by street.")
            }
        }
        .font(StrandFont.subhead)
        .foregroundStyle(StrandPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var batteryText: some View {
        Group {
            switch mode {
            case .eco: Text("Battery: very low")
            case .balanced: Text("Battery: moderate")
            case .precise: Text("Battery: high")
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
    }

    private func batteryColor(_ level: Int) -> Color {
        let filled: Int
        switch mode {
        case .eco: filled = 1
        case .balanced: filled = 2
        case .precise: filled = 3
        }
        guard level <= filled else { return StrandPalette.surfaceOverlay }
        return filled == 3 ? StrandPalette.statusWarning : StrandPalette.statusPositive
    }

    // MARK: Frequency

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .balanced {
                Text("A point every").strandOverline()
            } else {
                Text("A point every (distance)").strandOverline()
            }
            HStack(spacing: 6) {
                if mode == .balanced {
                    ForEach(PlaceTrackingSettings.intervalChoices, id: \.self) { minutes in
                        chip(String(localized: "\(minutes) min"), active: interval == minutes) {
                            interval = minutes
                            apply()
                        }
                    }
                } else {
                    ForEach(PlaceTrackingSettings.distanceChoices, id: \.self) { meters in
                        chip(String(localized: "\(meters) m"), active: distance == meters) {
                            distance = meters
                            apply()
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(active ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(active ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: When

    private var quietRanges: [PlaceQuietRange] {
        (try? JSONDecoder().decode([PlaceQuietRange].self, from: quietRangesData)) ?? []
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When").strandOverline()
            VStack(alignment: .leading, spacing: 0) {
                settingsToggle("Pause when still", subtitle: nil,
                               isOn: Binding(get: { pauseWhenStill }, set: { pauseWhenStill = $0; apply() }))
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                settingsToggle("No points at night",
                               subtitle: "23:00 – 07:00 · the night counts for the place you went to bed",
                               isOn: Binding(get: { quietNight }, set: { quietNight = $0; apply() }))
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                NavigationLink {
                    PlaceQuietRangesView()
                } label: {
                    HStack {
                        Text("Other spans with no points")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        Text(verbatim: PlaceTrackingSettings.rangesLabel(quietRanges) + " ›")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(NoopPanelSurface(cornerRadius: 26))
            Text("During a GPS workout, the route is still recorded every second, whatever this setting.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsToggle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?,
                                isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
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
        }
        .toggleStyle(.switch)
        .tint(StrandPalette.switchOn)
        .frame(minHeight: 44)
    }

    // MARK: Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data").strandOverline()
            HStack {
                Text("Keep the points")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(PlaceTrackingSettings.keepChoices, id: \.self) { days in
                        Button(PlaceKeepChoice.keepLabel(days)) {
                            keepPointsDays = days
                            PlaceTracker.shared.applyRetentionNow()
                        }
                    }
                } label: {
                    Text(verbatim: PlaceKeepChoice.keepLabel(keepPointsDays) + " ›")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(NoopPanelSurface(cornerRadius: 26))
        }
    }
}

// MARK: - Other quiet spans

struct PlaceQuietRangesView: View {
    @AppStorage(PlaceTrackingSettings.quietRangesKey) private var quietRangesData = Data()
    @State private var newStart = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var newEnd = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()

    private var ranges: [PlaceQuietRange] {
        (try? JSONDecoder().decode([PlaceQuietRange].self, from: quietRangesData)) ?? []
    }

    private func save(_ ranges: [PlaceQuietRange]) {
        quietRangesData = (try? JSONEncoder().encode(ranges)) ?? Data()
        PlaceTracker.shared.applyPlaceSettings()
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var body: some View {
        ScreenScaffold(title: "Spans with no points") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if !ranges.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ranges.enumerated()), id: \.element.id) { index, range in
                            if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
                            HStack {
                                Text(verbatim: PlaceTrackingSettings.rangeLabel(range))
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: 8)
                                Button {
                                    save(ranges.filter { $0 != range })
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(StrandPalette.statusCritical)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove"))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(NoopPanelSurface(cornerRadius: 26))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add a span").strandOverline()
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("From", selection: $newStart, displayedComponents: .hourAndMinute)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        DatePicker("To", selection: $newEnd, displayedComponents: .hourAndMinute)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Button {
                            let range = PlaceQuietRange(startMinute: Self.minuteOfDay(newStart),
                                                        endMinute: Self.minuteOfDay(newEnd))
                            guard range.startMinute != range.endMinute, !ranges.contains(range) else { return }
                            save(ranges + [range])
                        } label: {
                            Text("Add")
                                .font(StrandFont.body.weight(.semibold))
                                .foregroundStyle(StrandPalette.surfaceBase)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(StrandPalette.textPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(NoopPanelSurface(cornerRadius: 26))
                }
                Text("Every day, no point is kept in these spans. Visits are still recorded, so the places stay right.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Known places

struct KnownPlacesView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PlaceLog.revisionKey) private var revision = 0
    @State private var places: [PlaceRow] = []
    @State private var renaming: PlaceRow?
    @State private var draftName = ""

    var body: some View {
        ScreenScaffold(title: "Known places") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if places.isEmpty {
                    Text("No place yet. iOS reports a place after you have stayed there a while.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                            if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
                            HStack {
                                Text(verbatim: PlaceNaming.placeName(place, in: places))
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: 8)
                                Menu {
                                    Button("Rename") {
                                        draftName = place.name ?? ""
                                        renaming = place
                                    }
                                    Button("Forget this place", role: .destructive) {
                                        Task {
                                            guard let store = await repo.storeHandle() else { return }
                                            await PlaceLog.forgetKnownPlace(store, id: place.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(Text("Actions"))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(NoopPanelSurface(cornerRadius: 26))
                }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Save") {
                guard let place = renaming else { return }
                let name = draftName
                Task {
                    guard let store = await repo.storeHandle() else { return }
                    await PlaceLog.renameKnownPlace(store, id: place.id, name: name)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .task(id: revision) {
            guard let store = await repo.storeHandle() else { return }
            places = await PlaceLog.places(store)
        }
    }
}
