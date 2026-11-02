import WidgetKit
import SwiftUI
import StrandDesign

// The three day widgets (personal fork, chantier 6): "Today's session", "Nutrition" and "Sleep", small and
// medium. They read `DayWidgetsSnapshot` from the App Group — the app words and formats everything — and draw
// it with the faces in `StrandiOSShared/DayWidgetViews.swift`. Past the day the snapshot describes, a widget
// says "no data" until the app publishes the new day.

struct DayWidgetsEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has published anything.
    let snapshot: DayWidgetsSnapshot?

    /// The snapshot's words, English before the app has published.
    var labels: DayWidgetsSnapshot.Labels { snapshot?.labels ?? .english }

    /// The snapshot while its day lasts; nil once the day is over.
    var current: DayWidgetsSnapshot? {
        guard let snapshot, snapshot.isCurrent(at: date) else { return nil }
        return snapshot
    }
}

struct DayWidgetsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayWidgetsEntry {
        DayWidgetsEntry(date: Date(), snapshot: .galleryPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayWidgetsEntry) -> Void) {
        let stored = DayWidgetsSnapshot.loadDayWidgets(suiteName: WidgetSnapshot.suiteName)
        let current = stored.flatMap { $0.isCurrent(at: Date()) ? $0 : nil }
        // The gallery shows the wearer's own day when there is one, else the mockup's sample.
        completion(DayWidgetsEntry(date: Date(), snapshot: context.isPreview ? (current ?? .galleryPreview) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayWidgetsEntry>) -> Void) {
        let now = Date()
        let stored = DayWidgetsSnapshot.loadDayWidgets(suiteName: WidgetSnapshot.suiteName)
        var entries = [DayWidgetsEntry(date: now, snapshot: stored)]
        // A second entry at the day's end turns the figures into "no data" on time, app open or not.
        if let end = stored?.validUntil, end > now {
            entries.append(DayWidgetsEntry(date: end, snapshot: stored))
        }
        // The app reloads these widgets when their section changes; this is the safety net.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
    }
}

/// The face for the widget's family: medium, else small.
private func daySize(_ family: WidgetFamily) -> DayWidgetSize {
    family == .systemMedium ? .medium : .small
}

struct DaySessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayWidgetsEntry

    var body: some View {
        DaySessionWidgetFace(session: entry.current?.session, labels: entry.labels, size: daySize(family))
            .overlay(alignment: .bottomLeading) { DayWidgetsGroupNote(entry: entry) }
            .widgetURL(DayWidgetsSnapshot.Link.session.url)
    }
}

struct DayNutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayWidgetsEntry

    var body: some View {
        DayNutritionWidgetFace(nutrition: entry.current?.nutrition, labels: entry.labels, size: daySize(family))
            .overlay(alignment: .bottomLeading) { DayWidgetsGroupNote(entry: entry) }
            .widgetURL(DayWidgetsSnapshot.Link.nutrition.url)
    }
}

struct DaySleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayWidgetsEntry

    var body: some View {
        DaySleepWidgetFace(sleep: entry.current?.sleep, labels: entry.labels, size: daySize(family))
            .overlay(alignment: .bottomLeading) { DayWidgetsGroupNote(entry: entry) }
            .widgetURL(DayWidgetsSnapshot.Link.sleep.url)
    }
}

/// Nothing ever read from the App Group: the group this extension reads and whether its signature grants it
/// ("group.… ✓" / "✗"), so a sideload that left the widgets outside the app's group says so on screen.
private struct DayWidgetsGroupNote: View {
    let entry: DayWidgetsEntry

    var body: some View {
        if entry.snapshot == nil {
            Text(WidgetSnapshot.suiteNameDiagnostic)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 190, alignment: .leading)
        }
    }
}

/// The gallery's words: the app's language once it has published, English before.
private var galleryLabels: DayWidgetsSnapshot.Labels {
    DayWidgetsSnapshot.loadDayWidgets(suiteName: WidgetSnapshot.suiteName)?.labels ?? .english
}

struct DaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayWidgetsSnapshot.sessionKind, provider: DayWidgetsProvider()) { entry in
            DaySessionWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceRaised, for: .widget)
        }
        .configurationDisplayName(galleryLabels.sessionTitle)
        .description(galleryLabels.sessionAbout)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DayNutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayWidgetsSnapshot.nutritionKind, provider: DayWidgetsProvider()) { entry in
            DayNutritionWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceRaised, for: .widget)
        }
        .configurationDisplayName(galleryLabels.nutritionTitle)
        .description(galleryLabels.nutritionAbout)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DaySleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayWidgetsSnapshot.sleepKind, provider: DayWidgetsProvider()) { entry in
            DaySleepWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceRaised, for: .widget)
        }
        .configurationDisplayName(galleryLabels.sleepTitle)
        .description(galleryLabels.sleepAbout)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
