//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Observation

extension Container {

    var newEpisodesTracker: Factory<NewEpisodesTracker> {
        self { MainActor.assumeIsolated { NewEpisodesTracker() } }.singleton
    }
}

/// Finds series the user started that gained episodes after they last watched them.
///
/// Series carry no last played date of their own, so it comes from the user's recently watched episodes.
@MainActor
@Observable
final class NewEpisodesTracker {

    /// When the newest episode was added, for each series with episodes the user hasn't been back for
    private var newestEpisodeDates: [String: Date] = [:]

    @ObservationIgnored
    private var storeChanges: Set<AnyCancellable> = []

    func hasNewEpisodes(seriesID: String) -> Bool {
        newestEpisodeDates[seriesID] != nil
    }

    func refresh(userSession: UserSession) async {
        do {
            let lastWatchedDates = try await lastWatchedDates(userSession: userSession)
            let series = try await series(ids: Array(lastWatchedDates.keys), userSession: userSession)

            let newestEpisodeDates: [String: Date] = series.reduce(into: [:]) { dates, series in
                guard let id = series.id,
                      let newestEpisodeDate = series.dateLastMediaAdded,
                      let lastWatchedDate = lastWatchedDates[id],
                      newestEpisodeDate > lastWatchedDate,
                      series.userData?.isPlayed != true
                else { return }

                dates[id] = newestEpisodeDate
            }

            // Every poster reads these, so only publish real changes
            if newestEpisodeDates != self.newestEpisodeDates {
                self.newestEpisodeDates = newestEpisodeDates
            }

            observe(userSession)
        } catch {
            // Keep the last known badges until the next refresh succeeds
        }
    }

    /// Keeps badges current while the app stays open
    private func observe(_ userSession: UserSession) {
        let refreshes = PassthroughSubject<Void, Never>()

        storeChanges = [
            userSession.items
                .changes
                .sink { [weak self, weak userSession] change in
                    switch change {
                    case let .updated(update) where update.userDataChanged:
                        // Items that aren't loaded can't say which series they belong to, so ask the server
                        if let item = userSession?.items[update.itemID]?.value {
                            self?.clearIfWatched(item)
                        } else {
                            refreshes.send()
                        }

                    case .libraryChanged:
                        // New episodes arrive this way
                        refreshes.send()

                    case .invalidated:
                        self?.newestEpisodeDates = [:]

                    default: ()
                    }
                },
            // Changes come in bursts, like during a library scan
            refreshes
                .debounce(for: .seconds(10), scheduler: RunLoop.main)
                .sink { [weak self, weak userSession] in
                    guard let self, let userSession else { return }

                    Task { await self.refresh(userSession: userSession) }
                },
        ]
    }

    private func clearIfWatched(_ episode: BaseItemDto) {
        guard let seriesID = episode.seriesID,
              let newestEpisodeDate = newestEpisodeDates[seriesID],
              let lastPlayedDate = episode.userData?.lastPlayedDate,
              lastPlayedDate >= newestEpisodeDate
        else { return }

        newestEpisodeDates[seriesID] = nil
    }

    /// The last time the user played an episode of each recently watched series
    private func lastWatchedDates(userSession: UserSession) async throws -> [String: Date] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableImages = false
        parameters.enableUserData = true
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = 100
        parameters.sortBy = [.datePlayed]
        parameters.sortOrder = [.descending]
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getItems(parameters: parameters))

        // Newest first, so the first episode of each series has its last played date
        return (response.value.items ?? []).reduce(into: [:]) { dates, episode in
            guard let seriesID = episode.seriesID, let lastPlayedDate = episode.userData?.lastPlayedDate else { return }

            dates[seriesID] = dates[seriesID] ?? lastPlayedDate
        }
    }

    private func series(ids: [String], userSession: UserSession) async throws -> [BaseItemDto] {
        guard ids.isNotEmpty else { return [] }

        var parameters = Paths.GetItemsParameters()
        parameters.enableImages = false
        parameters.enableUserData = true
        parameters.fields = [.dateLastMediaAdded]
        parameters.ids = ids
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getItems(parameters: parameters))

        return response.value.items ?? []
    }
}
