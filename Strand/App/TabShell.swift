import SwiftUI
import StrandDesign

// MARK: - Tab shell hooks (fork chantier 9)
//
// The iPhone shell has five tabs (Today, Training, Nutrition, Sleep, Coach) and opens everything else
// from the profile picture at the top right of each tab, as a sheet. The screens the tabs host are
// shared with macOS, which keeps its sidebar, so both hooks below are off by default: the iOS shell
// turns them on, and a macOS window or a render test sees the screens exactly as before.

/// Lets a link on a tab root switch tabs instead of pushing a second copy of a screen that is already a
/// tab (Today's session row → Training, its nutrition line → Nutrition, its sleep rows → Sleep).
struct TabRouteSwitch {
    /// Whether the shell shows `route` as a tab of its own.
    var handles: (TabRoute) -> Bool
    /// Selects that tab.
    var open: (TabRoute) -> Void
}

private struct TabRouteSwitchKey: EnvironmentKey {
    static let defaultValue: TabRouteSwitch? = nil
}

private struct ShowsMoreAvatarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by the iOS tab shell; nil elsewhere, where every route pushes.
    var tabRouteSwitch: TabRouteSwitch? {
        get { self[TabRouteSwitchKey.self] }
        set { self[TabRouteSwitchKey.self] = newValue }
    }

    /// True inside the iOS tab shell: the tab roots then show the profile picture that opens More.
    var showsMoreAvatar: Bool {
        get { self[ShowsMoreAvatarKey.self] }
        set { self[ShowsMoreAvatarKey.self] = newValue }
    }
}

/// A row that opens `route`: by switching tabs when the shell shows that route as a tab, by pushing the
/// route's value on the current stack otherwise (so the first hop still rides the tab's path, #198).
struct TabRouteLink<Label: View>: View {
    let route: TabRoute
    @ViewBuilder let label: () -> Label
    @Environment(\.tabRouteSwitch) private var tabSwitch

    init(route: TabRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.label = label
    }

    var body: some View {
        if let tabSwitch, tabSwitch.handles(route) {
            Button { tabSwitch.open(route) } label: { label() }
        } else {
            NavigationLink(value: route) { label() }
        }
    }
}

/// The profile picture at the top right of every tab root: it opens the More sheet. Renders nothing
/// outside the iOS tab shell, so a header that adds it is unchanged on macOS and in render tests.
struct MoreAvatarButton: View {
    @Environment(\.showsMoreAvatar) private var shows

    var body: some View {
        if shows {
            MoreAvatarButtonContent()
        }
    }
}

/// Split from `MoreAvatarButton` so the environment objects are only read where the shell provides them.
private struct MoreAvatarButtonContent: View {
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        Button { router.openMore() } label: {
            Color.clear.frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
        }
        .nativeLiquidGlassHeaderButton()
        .overlay {
            GeometryReader { proxy in
                let diameter = min(proxy.size.width, proxy.size.height)
                ProfileAvatarView(imageData: profile.avatarImageData, size: diameter)
                    .frame(width: diameter, height: diameter)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)
        }
        .nativeLiquidGlassPhotoFinish()
        .accessibilityLabel("More")
    }
}
