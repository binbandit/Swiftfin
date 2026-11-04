//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@MainActor
final class TabCoordinator: ObservableObject {

    struct SelectedEvent {
        let isRoot: Bool
        let isRepeat: Bool
    }

    typealias TabData = (
        item: TabItem,
        coordinator: NavigationCoordinator,
        publisher: TabItemSelectedPublisher
    )

    @Published
    var selectedTabID: String! = nil {
        didSet {
            guard let tab = tabs.first(property: \.item.id, equalTo: selectedTabID) else { return }

            tab.publisher.send(
                .init(
                    isRoot: tab.coordinator.path.isEmpty,
                    isRepeat: oldValue == selectedTabID
                )
            )
        }
    }

    let tabs: [TabData]

    init(@ArrayBuilder<TabItem> tabs: () -> [TabItem]) {
        let tabs = tabs()
        self.tabs = tabs.map { tab in
            (tab, NavigationCoordinator(), TabItemSelectedPublisher())
        }
        self.selectedTabID = tabs.first?.id
    }

    func route(to route: NavigationRoute) async {
        guard let tab = tabs.first(where: { $0.item.id == selectedTabID }) else { return }

        tab.coordinator.push(route)
    }

    /// Shows a route over the selected tab's root page, closing pages left open first, such as a paused player
    func open(_ route: NavigationRoute) async {
        guard let coordinator = tabs.first(where: { $0.item.id == selectedTabID })?.coordinator else { return }

        withTransaction(\.disablesAnimations, true) {
            coordinator.path.removeAll()
            coordinator.presentedSheet = nil
            coordinator.presentedFullScreen = nil
        }

        // A page presented before the others finish closing is dropped
        for _ in 0 ..< 40 {
            guard UIApplication.shared.keyWindow?.rootViewController?.presentedViewController != nil else { break }

            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.push(route)
    }
}
