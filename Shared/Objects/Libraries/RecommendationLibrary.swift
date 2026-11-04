//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// A row of titles picked for the user when Home is built, so it never reshuffles while visible.
struct RecommendationLibrary: PagingLibrary {

    let entries: [ItemEntry]
    let hasNextPage = false
    let parent: TitledLibraryParent

    init(title: String, id: String, entries: [ItemEntry]) {
        self.entries = entries
        self.parent = .init(displayTitle: title, id: id)
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [ItemEntry] {
        entries
    }

    // Titles the user starts move to Continue Watching
    func includes(_ element: ItemEntry, environment: Empty) -> Bool {
        (element.item.confirmedUserData?.playbackPositionTicks ?? 0) == 0
    }

    func shouldRefreshForUserDataChange(environment: Empty) -> Bool {
        true
    }
}
