//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import TVServices

/// Shows the rows the app last stored, falling back to the static Top Shelf image when there are none,
/// such as when the user is signed out.
final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let snapshot = TopShelfSnapshot.load() else { return nil }

        let sections = snapshot.sections.map { section in
            let collection = TVTopShelfItemCollection(items: section.items.map(Self.sectionedItem))
            collection.title = section.title
            return collection
        }

        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func sectionedItem(for item: TopShelfSnapshot.Item) -> TVTopShelfSectionedItem {
        let sectionedItem = TVTopShelfSectionedItem(identifier: item.id)

        sectionedItem.title = item.title
        sectionedItem.imageShape = .hdtv
        sectionedItem.playbackProgress = item.progress
        sectionedItem.setImageURL(item.imageURL, for: [.screenScale1x, .screenScale2x])
        sectionedItem.displayAction = TVTopShelfAction(url: item.displayURL)
        sectionedItem.playAction = TVTopShelfAction(url: item.playURL)

        return sectionedItem
    }
}
