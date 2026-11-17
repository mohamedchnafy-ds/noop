import WidgetKit
import SwiftUI

/// The widget extension entry point. Bundles the glanceable widget, the live-HR Live Activity,
/// the K10 Coach brief widget (stored morning brief on Lock Screen / Home Screen), the
/// heart-rate trace widget (#1957), the stress curve widget (#2040), the Lift Log session
/// Live Activity, the strap-sync Live Activity, and the three day widgets — today's session, nutrition and
/// sleep (personal fork, chantier 6), then a nested bundle with the fasting Live Activity (chantier 15) and
/// the habit stopwatch Live Activity (chantier 24): `WidgetBundleBuilder` takes ten entries at most.
@main
struct NOOPWidgetBundle: WidgetBundle {
    var body: some Widget {
        NOOPWidget()
        NOOPLiveActivity()
        // Widgets v2 (personal fork, 5 Nov.): the Coach brief widget left the gallery at Mohamed's request.
        HeartRateWidget()
        StressWidget()
        LiftLiveActivity()
        SyncLiveActivity()
        DaySessionWidget()
        DayNutritionWidget()
        DaySleepWidget()
        // `WidgetBundleBuilder` takes ten entries at most: the eleventh and beyond live in a nested bundle.
        NOOPWidgetBundleMore().body
    }
}

/// The widgets past the tenth (personal fork, chantier 24 PR C): the fasting banner (chantier 15) and the
/// habit stopwatch banner. Not `@main`: `NOOPWidgetBundle` includes its body.
struct NOOPWidgetBundleMore: WidgetBundle {
    var body: some Widget {
        FastingLiveActivity()
        HabitLiveActivity()
    }
}
