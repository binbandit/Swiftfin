//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

struct DefaultContentGroupProvider: ContentGroupProvider {

    @Injected(\.currentUserSession)
    var userSession: UserSession?

    @Injected(\.newEpisodesTracker)
    private var newEpisodesTracker

    let displayTitle: String = L10n.home
    let id: String = "default-content-group-provider"

    // Rebuilds Home when its settings change, so they apply without a relaunch
    var refreshRequests: AnyPublisher<ContentGroupRefreshRequest, Never> {
        Defaults.publisher(
            keys: .Customization.Home.showRecentlyAdded,
            .Customization.Home.showRecentlyPlayed,
            .Customization.Home.showHolidays,
            .Customization.Home.showBecauseYouWatched,
            .Customization.Home.showTopGenres,
            .Customization.Home.resumeNextUp,
            .Customization.Home.maxNextUp,
            options: []
        )
        .map { ContentGroupRefreshRequest() }
        .eraseToAnyPublisher()
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        guard let userSession else { return [] }

        // Personal rows and badges load before Home appears, so nothing pops in while it's on screen
        async let recommendations = HomeRecommendations.rows(
            for: userSession,
            includesWatched: Defaults[.Customization.Home.showBecauseYouWatched],
            includesGenres: Defaults[.Customization.Home.showTopGenres]
        )
        async let newEpisodes: Void = newEpisodesTracker.refresh(userSession: userSession)

        let parameters = Paths.GetUserViewsParameters(userID: userSession.user.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        let userViews = try await userSession.send(userViewsPath)
        let excludedLibraryIDs = userSession.user.data.configuration?.latestItemsExcludes ?? []

        let resolvedUserViews = (userViews.value.items ?? [])
            .subtracting(excludedLibraryIDs, using: \.id)
            .intersecting(
                [
                    .homevideos,
                    .movies,
                    .musicvideos,
                    .tvshows,
                ],
                using: \.collectionType
            )

        await newEpisodes

        return await _makeGroups(userViews: resolvedUserViews, recommendations: recommendations)
    }

    @ContentGroupBuilder
    private func _makeGroups(
        userViews: [BaseItemDto],
        recommendations: [HomeRecommendations.Row]
    ) -> [any ContentGroup] {

        let recommendationGroups: [any ContentGroup] = recommendations.map { row in
            PosterGroup(
                id: row.id,
                library: RecommendationLibrary(title: row.title, id: row.id, entries: row.entries)
            )
        }

        #if os(tvOS)
        let cinematicSelectionContentGroup = CinematicSelectionContentGroup(
            resumeLibrary: ResumeItemsLibrary(mediaTypes: [.video]),
            recentlyAddedLibrary: RecentlyAddedLibrary()
        )

        cinematicSelectionContentGroup
        #else
        PosterGroup(
            library: ResumeItemsLibrary(mediaTypes: [.video]),
            posterDisplayType: .landscape,
            posterSize: .medium,
            _viewContext: .isInResume
        )
        #endif

        PosterGroup(
            library: NextUpLibrary()
        )

        if Defaults[.Customization.Home.showHolidays], let holiday = Holiday.current {
            PosterGroup(
                id: "holiday-\(holiday.rawValue)",
                library: ItemLibrary(
                    parent: BaseItemDto(name: holiday.displayTitle),
                    filters: .init(sortBy: [.random]),
                    staticFilters: .init(itemTypes: [.movie, .series], tags: holiday.tags)
                )
            )
        }

        if Defaults[.Customization.Home.showRecentlyAdded] {
            #if os(tvOS)
            CinematicRecentlyAddedContentGroup(
                viewModel: cinematicSelectionContentGroup.viewModel
            )
            #else
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyAdded.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.dateCreated],
                        sortOrder: [.descending]
                    )
                )
            )
            #endif
        }

        // The first personal row breaks up Recently Added and the Latest rows, so neither gets buried
        Array(recommendationGroups.prefix(1))

        if Defaults[.Customization.Home.showRecentlyPlayed] {
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: L10n.recentlyPlayed.localizedCapitalized),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.datePlayed],
                        sortOrder: [.descending],
                        traits: [.isPlayed]
                    )
                )
            )
        }

        PosterGroup(
            id: "programs-recommended",
            library: RecommendedProgramsLibrary(),
            posterDisplayType: .landscape,
            posterSize: .small
        )

        userViews
            .map(LatestInLibrary.init)
            .map {
                PosterGroup(
                    library: $0,
                    posterDisplayType: .landscape
                )
            }

        Array(recommendationGroups.dropFirst())
    }
}
