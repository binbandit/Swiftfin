//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The Top Shelf rows the app shares with its Top Shelf extension through their App Group.
///
/// The app resolves every title, image URL, and deep link, so the extension never needs the user's credentials.
struct TopShelfSnapshot: Codable, Equatable {

    struct Section: Codable, Equatable {

        let title: String
        let items: [Item]
    }

    struct Item: Codable, Equatable {

        let id: String
        let title: String
        let imageURL: URL?
        /// The fraction watched, from 0 to 1
        let progress: Double
        let displayURL: URL
        let playURL: URL
    }

    let sections: [Section]
}

extension TopShelfSnapshot {

    private static let fileURL = (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
        .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
        .appending(path: "TopShelfSnapshot.json")

    /// The stored snapshot, or nil when there's nothing to show
    static func load() -> Self? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }

        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Replaces the stored snapshot, removing it when nil
    static func store(_ snapshot: Self?) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }

        if let snapshot {
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: fileURL.path()) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
