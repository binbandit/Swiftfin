//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import Transmission

// TODO: have full screen zoom presentation zoom from/to center
//       - probably need to make mock view with matching ids

struct PresentationControllerShouldDismissPreferenceKey: PreferenceKey {

    static var defaultValue: Bool = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct NavigationInjectionView: View {

    @StateObject
    private var coordinator: NavigationCoordinator

    @State
    private var isPresentationInteractive: Bool = true

    private let content: AnyView

    init(
        coordinator: @autoclosure @escaping () -> NavigationCoordinator,
        @ViewBuilder content: @escaping () -> some View
    ) {
        _coordinator = StateObject(wrappedValue: coordinator())
        self.content = AnyView(content())
    }

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            content
                .trackingFrame(for: .layoutContainer)
                .navigationDestination(for: NavigationRoute.self) { route in
                    route.destination
                        .trackingFrame(for: .layoutContainer)
                        .environment(
                            \.router,
                            .init(
                                navigationCoordinator: coordinator,
                                isRootOfPath: false
                            )
                        )
                }
        }
        .trackingFrame(for: .navigationStack)
        #if os(tvOS)
        .modifier(HiddenUnderPushModifier(coordinator: coordinator))
        #endif
        .environment(
            \.router,
            .init(
                navigationCoordinator: coordinator,
                isRootOfPath: true
            )
        )
        .environmentObject(coordinator)
        #if os(tvOS)
        .fullScreenCover(
            item: $coordinator.presentedSheet
        ) {
            coordinator.presentedSheet = nil
        } content: { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
            .presentedOverTabView()
            // A sheet floats over the page beneath it.
            .if(!presentedRoute.route.isPush) { view in
                view.background(.regularMaterial)
            }
            // A push replaces the page beneath it, which hides. Dismissing through state
            // brings that page back as the push fades out, rather than after.
            .if(presentedRoute.route.isPush) { view in
                view.onExitCommand {
                    coordinator.presentedSheet = nil
                }
            }
        }
        .fullScreenCover(
            item: $coordinator.presentedFullScreen
        ) { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
            .presentedOverTabView()
        }
        #else
        .sheet(
            item: $coordinator.presentedSheet
        ) {
            coordinator.presentedSheet = nil
        } content: { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
        }
        .presentation(
            $coordinator.presentedFullScreen,
            transition: .zoomIfAvailable(
                .init(
                    dimmingVisualEffect: .systemThickMaterialDark,
                    prefersScalePresentingView: false
                ),
                options: .init(
                    isInteractive: isPresentationInteractive,
                    modalPresentationCapturesStatusBarAppearance: true,
                    preferredPresentationSafeAreaInsets: .zero,
                ),
                otherwise: .slide(
                    .init(edge: .bottom),
                    options: .init(
                        isInteractive: isPresentationInteractive,
                        modalPresentationCapturesStatusBarAppearance: true
                    )
                )
            )
        ) { presentedRouteBinding, _ in
            let vc = UIPreferencesHostingController {
                NavigationInjectionView(coordinator: presentedRouteBinding.wrappedValue.coordinator) {
                    presentedRouteBinding.wrappedValue
                        .route
                        .destination
                        .onPreferenceChange(PresentationControllerShouldDismissPreferenceKey.self) { newValue in
                            isPresentationInteractive = newValue
                        }
                }
            }

            vc.view.backgroundColor = .black

            return vc
        }
        #endif
    }
}

#if os(tvOS)
private extension View {

    /// A presentation covers the whole tab view, sidebar included, so it neither takes the tab view's frame
    /// nor the tab content's disabled state, which tvOS sets while its sidebar is open, such as at launch
    func presentedOverTabView() -> some View {
        transformEnvironment(\.frameForParentView) { $0[.tabView] = nil }
            .environment(\.isEnabled, true)
    }
}

/// tvOS presents a push over the page that it replaces, so hide that page underneath,
/// leaving the pushed page on the same app background as the root.
struct HiddenUnderPushModifier: ViewModifier {

    @ObservedObject
    var coordinator: NavigationCoordinator

    func body(content: Content) -> some View {
        content
            .animation(.easeInOut(duration: 0.3)) { page in
                page
                    .opacity(coordinator.isPresentingPush ? 0 : 1)
            }
    }
}
#endif
