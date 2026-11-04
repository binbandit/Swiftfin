//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Algorithms
import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import TVServices
import UIKit

/// Keeps the Top Shelf's Continue Watching and Up Next rows in step with the signed-in user.
///
/// The rows come from the libraries behind Home's rows. They refresh when a session starts, when progress or
/// libraries change, and as the app leaves for the Home Screen, where the Top Shelf appears.
@MainActor
final class TopShelfSnapshotWriter {

    private static let itemLimit = 10

    @Injected(\.userSessionManager)
    private var userSessionManager

    private let logger = Logger.swiftfin()
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?

    init() {
        userSessionManager.$currentSession
            .map { session -> AnyPublisher<Void, Never> in
                guard let session else { return Just(()).eraseToAnyPublisher() }

                return session.items
                    .changes
                    .filter(\.changesRows)
                    .map { _ in }
                    // The rows leave out titles without media, which a check can find after they're written
                    .merge(with: session.titleAvailability.changes)
                    .prepend(())
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            // Coalesce bursts, such as a finished episode also updating its season and series
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        Notifications[.applicationDidEnterBackground]
            .publisher
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Refreshes after any refresh underway so an older response can't replace a newer one,
    /// keeping the app awake meanwhile since it may be leaving for the Home Screen.
    private func refresh() {
        let previousRefresh = refreshTask
        let refresh = Task {
            await previousRefresh?.value
            await writeSnapshot()
        }

        refreshTask = refresh

        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Refresh Top Shelf",
            expirationHandler: { refresh.cancel() }
        )

        Task {
            await refresh.value
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    private func writeSnapshot() async {
        // Wait for the stored session to be restored
        guard userSessionManager.state != .initial else { return }

        do {
            var snapshot: TopShelfSnapshot?

            if let userSession = userSessionManager.currentSession {
                snapshot = try await makeSnapshot(for: userSession)
            }

            guard snapshot != TopShelfSnapshot.load() else { return }

            try TopShelfSnapshot.store(snapshot)
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            guard !Task.isCancelled else { return }

            // The previous rows stay, such as while the server is unreachable
            logger.error(
                "Unable to refresh the Top Shelf",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    /// Returns nil when there's nothing to continue, so the Top Shelf shows its static image
    private func makeSnapshot(for userSession: UserSession) async throws -> TopShelfSnapshot? {
        let resumePage = try LibraryPageState(pageOffset: 0, pageSize: Self.itemLimit, userSession: userSession)
        // Next Up repeats episodes that are in progress, so fetch extra to fill the row without them
        let nextUpPage = try LibraryPageState(pageOffset: 0, pageSize: Self.itemLimit * 2, userSession: userSession)

        async let resumePatches = ResumeItemsLibrary().retrievePage(environment: .default, pageState: resumePage)
        async let nextUpPatches = NextUpLibrary().retrievePage(environment: .default, pageState: nextUpPage)

        // Tiles show an episode's series art, so each series appears once
        let continueWatching = try await resumePatches.map(\.value).uniqued(on: \.seriesOrItemID)
        let watchingIDs = Set(continueWatching.map(\.seriesOrItemID))
        let upNext = try await nextUpPatches.map(\.value)
            .filter { !watchingIDs.contains($0.seriesOrItemID) }
            .uniqued(on: \.seriesOrItemID)
            .prefix(Self.itemLimit)

        let sections = [
            makeSection(title: L10n.continueWatching, items: continueWatching, in: userSession),
            makeSection(title: L10n.nextUp, items: Array(upNext), in: userSession),
        ].compacted()

        return sections.isEmpty ? nil : TopShelfSnapshot(sections: Array(sections))
    }

    private func makeSection(title: String, items: [BaseItemDto], in userSession: UserSession) -> TopShelfSnapshot.Section? {
        let items = items.compactMap { makeItem(for: $0, in: userSession) }

        return items.isEmpty ? nil : TopShelfSnapshot.Section(title: title, items: items)
    }

    private func makeItem(for item: BaseItemDto, in userSession: UserSession) -> TopShelfSnapshot.Item? {
        guard let id = item.id,
              let displayURL = DeepLink(serverID: userSession.server.id, userID: userSession.user.id, destination: .item(id: id)).url,
              let playURL = DeepLink(serverID: userSession.server.id, userID: userSession.user.id, destination: .play(id: id)).url
        else { return nil }

        return TopShelfSnapshot.Item(
            id: id,
            // The Top Shelf shows one line under the focused tile, such as "Brooklyn Nine-Nine · S1:E2 · 21 min left"
            title: [item.artworkTitle, item.seasonEpisodeLabel, item.timeLeft].compacted().joined(separator: " · "),
            imageURL: imageURL(for: item),
            progress: (item.userData?.playedPercentage ?? 0) / 100,
            displayURL: displayURL,
            playURL: playURL
        )
    }

    /// The art of Home's landscape cards, such as an episode's series art before its still
    private func imageURL(for item: BaseItemDto) -> URL? {
        let environment = BaseItemDto.Environment(
            maxWidth: TVTopShelfSectionedContent.imageSize(for: .hdtv).width,
            useParent: Defaults[.Customization.Poster.configuration].useSeriesLandscapeBackdrop,
            viewContext: .isThumb
        )

        var url: URL?

        // Sized for 2x so the art stays sharp on 4K displays
        UITraitCollection(displayScale: 2).performAsCurrent {
            url = item.imageSources(for: .landscape, environment: environment).first?.url
        }

        return url
    }
}

private extension BaseItemDto {

    var seriesOrItemID: String? {
        seriesID ?? id
    }

    var timeLeft: String? {
        guard let runtime, let position = startSeconds, position > .zero, position < runtime else { return nil }

        return (runtime - position).formatted(.timeLeft)
    }
}

private extension ItemStore.Change {

    /// Matches the changes that reload Home's resume and next up rows
    var changesRows: Bool {
        switch self {
        case let .updated(update):
            update.userDataChanged
        case .deleted, .libraryChanged:
            true
        case .invalidated:
            false
        }
    }
}
