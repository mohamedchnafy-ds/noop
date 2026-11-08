import SwiftUI
import StrandDesign

// MARK: - The gear of the Jeûne page (personal fork, chantier 15 PR C)
//
// The fast's notifications (planned end: on by default; halfway: off) and, on iOS, its Lock Screen banner.
// Each switch writes its UserDefaults key and re-runs the side effects through `FastingLog`, so the
// pending notifications and the banner follow at once. Nothing is sent anywhere.

struct FastingSettingsSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FastingNotifier.endEnabledKey) private var notifyEnd = true
    @AppStorage(FastingNotifier.halfEnabledKey) private var notifyHalf = false
    @AppStorage(UnitPrefs.fastingLiveActivityKey) private var bannerEnabled = true
    /// The wearer refused notifications for NOOP: say where to turn them on.
    @State private var denied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    toggleRow(Text("End of the fast"), Text("At the planned end: “16h of fasting reached”."), isOn: $notifyEnd)
                    toggleRow(Text("Halfway"), Text("At half the goal: how much is done and how much is left."), isOn: $notifyHalf)
                } header: {
                    Text("Notifications")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planned on the phone when the fast starts, moved when its start or its goal moves, removed when it stops. Nothing is sent anywhere.")
                        if denied {
                            Text("Notifications are off for NOOP: turn them on in the Settings app.")
                                .foregroundStyle(StrandPalette.statusWarning)
                        }
                    }
                }
                #if os(iOS)
                Section {
                    toggleRow(Text("Lock Screen banner"),
                              Text("Time done and left, with Stop, on the Lock Screen and in the Dynamic Island."),
                              isOn: $bannerEnabled)
                } header: {
                    Text("Live notifications")
                } footer: {
                    Text("iOS takes a banner down about 8 hours after it started. It comes back as soon as NOOP is opened while the fast runs.")
                }
                #endif
            }
            .navigationTitle(Text("Fasting settings"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .task { denied = await FastingNotifier.notificationsDenied() }
        .onChangeCompat(of: notifyEnd) { _ in resync() }
        .onChangeCompat(of: notifyHalf) { _ in resync() }
        .onChangeCompat(of: bannerEnabled) { _ in resync() }
    }

    private func toggleRow(_ title: Text, _ detail: Text, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(StrandFont.body)
                detail.font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .tint(StrandPalette.switchOn)
    }

    /// A switch moved: the pending notifications and the banner follow, and the authorization is asked for
    /// the first time a notification is planned.
    private func resync() {
        Task {
            guard let store = await repo.storeHandle() else { return }
            await FastingLog.resyncFastingSideEffects(store)
            denied = await FastingNotifier.notificationsDenied()
        }
    }
}
