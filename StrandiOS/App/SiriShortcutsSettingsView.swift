#if os(iOS)
import SwiftUI
import AppIntents
import StrandDesign

/// Surfaces NOOP's already-registered App Intents (see StrandiOS/System/NOOPAppIntents.swift) in the
/// UI so users discover them. `NOOPShortcuts` auto-registers "Sync Strap", "Buzz Strap", "Mark a Moment"
/// and "Ask Coach" with Siri/Spotlight/Shortcuts, but nothing in-app advertised them — this is the iOS
/// analogue of the Mac's strap-double-tap-runs-a-Shortcut feature. Apple's `SiriTipView`/`ShortcutsLink`
/// do exactly that: tip the user on the spoken phrase and deep-link into the Shortcuts app, scoped to
/// this app automatically. Fork chantier 17: the four actions in one group, the paragraphs in popovers.
struct SiriShortcutsSettingsView: View {
    var body: some View {
        ScreenScaffold(title: "Siri & Shortcuts",
                       subtitle: "Run NOOP actions hands-free.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                SettingsListGroup(caption: String(localized: "Ready-made actions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        SiriTipView(intent: SyncStrapIntent(), isVisible: .constant(true))
                            .siriTipViewStyle(.dark)
                        SiriTipView(intent: BuzzStrapIntent(), isVisible: .constant(true))
                            .siriTipViewStyle(.dark)
                        SiriTipView(intent: MarkMomentIntent(), isVisible: .constant(true))
                            .siriTipViewStyle(.dark)
                        // The fourth action, which the screen did not show before.
                        SiriTipView(intent: AskCoachIntent(), isVisible: .constant(true))
                            .siriTipViewStyle(.dark)
                    }
                    .padding(.vertical, NoopMetrics.space3)
                }
                SettingsListGroup(caption: String(localized: "Build your own")) {
                    HStack(spacing: NoopMetrics.space2) {
                        ShortcutsLink()
                        SettingsInfoPopover(text: String(localized: "Wire NOOP's actions into a Back-Tap, a focus automation, or a longer Shortcut. For example, double-tap the back of your iPhone to buzz the strap."))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, NoopMetrics.space3)
                }
            }
        }
        .noopEntranceRoot()
    }
}
#endif
