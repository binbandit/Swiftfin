//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Algorithms
import Foundation
import JellyfinAPI

/// Picks the personal Home rows from what the user recently watched.
///
/// Rows are picked together, so a title shows at most once across them
/// and never when it's already in Continue Watching, Next Up, or the user's recent history.
@MainActor
enum HomeRecommendations {

    struct Row {

        let id: String
        let title: String
        let entries: [ItemEntry]
    }

    private static let maxWatchedRows = 3
    private static let maxGenreRows = 3

    /// Rows in Home order, alternating "Because You Watched" style rows with genre rows
    static func rows(
        for userSession: UserSession,
        includesWatched: Bool,
        includesGenres: Bool
    ) async -> [Row] {
        guard includesWatched || includesGenres else { return [] }

        do {
            let requests = Requests(userSession: userSession)
            var picker = try RowPicker(store: userSession.items)

            async let history = requests.recentlyWatched()
            async let titlesOnHome = requests.titlesOnHome()
            async let recommendations = includesWatched ? requests.movieRecommendations() : []

            let watched = try await history
            picker.exclude(watched)
            try await picker.exclude(titlesOnHome)

            let titles = Array(watched.compactMap(WatchedTitle.init).uniqued(on: \.id))
            // The most recent movie and the most recent series
            let baselines = includesWatched ? Array(titles.uniqued(on: \.type)) : []
            let genres = includesGenres ? topGenres(in: titles) : []

            async let similarItems = baselines.concurrentMap { await (try? requests.similar(to: $0.id)) ?? [] }
            async let genreItems = genres.concurrentMap { await (try? requests.unwatched(genre: $0)) ?? [] }

            var watchedRows: [Row] = []

            for (baseline, candidates) in await zip(baselines, similarItems) {
                if let row = try picker.row(
                    id: "because-\(baseline.id)",
                    title: L10n.becauseYouWatched(baseline.name),
                    from: candidates
                ) {
                    watchedRows.append(row)
                }
            }

            // Fullest categories first within each kind
            let categories = try await recommendations
                .filter { recommendation in !baselines.contains { $0.id == recommendation.category.categoryID } }
                .sorted { ($0.priority, $1.items.count) < ($1.priority, $0.items.count) }

            for recommendation in categories where watchedRows.count < maxWatchedRows {
                guard let title = recommendation.title,
                      let row = try picker.row(id: recommendation.id, title: title, from: recommendation.items)
                else { continue }

                watchedRows.append(row)
            }

            var genreRows: [Row] = []

            for (genre, candidates) in await zip(genres, genreItems) where genreRows.count < maxGenreRows {
                if let row = try picker.row(id: "genre-\(genre)", title: genre, from: candidates) {
                    genreRows.append(row)
                }
            }

            return (0 ..< max(watchedRows.count, genreRows.count)).flatMap {
                [watchedRows[safe: $0], genreRows[safe: $0]].compacted()
            }
        } catch {
            // Personal rows are extras, so Home still loads without them
            return []
        }
    }

    /// The genres of the user's recent titles, ranked. One extra is kept in case a row comes up short.
    private static func topGenres(in titles: [WatchedTitle]) -> [String] {
        var tallies: [String: (count: Int, recency: Int)] = [:]

        for (recency, title) in titles.prefix(20).enumerated() {
            for genre in title.genres {
                tallies[genre, default: (0, recency)].count += 1
            }
        }

        // Most titles first, then the most recently watched
        let ranked = tallies
            .sorted { ($0.value.count, $1.value.recency) > ($1.value.count, $0.value.recency) }
            .map(\.key)

        // Skip genres that overlap a higher ranked one, like Action and Action & Adventure
        var picked: [String] = []

        for genre in ranked where picked.count <= maxGenreRows {
            let parts = Set(genre.components(separatedBy: " & "))

            if picked.allSatisfy({ parts.isDisjoint(with: $0.components(separatedBy: " & ")) }) {
                picked.append(genre)
            }
        }

        return picked
    }
}

/// A movie or series from the user's watch history. Episodes count toward their series.
private struct WatchedTitle {

    let id: String
    let name: String
    let type: BaseItemKind
    let genres: [String]

    init?(_ item: BaseItemDto) {
        switch item.type {
        case .movie:
            guard let id = item.id, let name = item.name else { return nil }

            self.id = id
            self.name = name
            self.type = .movie

        case .episode:
            guard let id = item.seriesID, let name = item.seriesName else { return nil }

            self.id = id
            self.name = name
            self.type = .series

        default:
            return nil
        }

        self.genres = item.genres ?? []
    }
}

/// Identifies a title on Home. Names also catch one title stored as separate items, like a series split across folders.
private enum TitleKey: Hashable {

    case id(String)
    case movie(name: String, year: Int?)
    case series(name: String)

    static func keys(for item: BaseItemDto) -> Set<TitleKey> {
        switch item.type {
        case .episode:
            // Episodes stand in for their series
            Set([item.seriesID.map(TitleKey.id), item.seriesName.map { .series(name: $0.lowercased()) }].compacted())
        case .series:
            Set([item.id.map(TitleKey.id), item.name.map { .series(name: $0.lowercased()) }].compacted())
        default:
            Set([item.id.map(TitleKey.id), item.name.map { .movie(name: $0.lowercased(), year: item.productionYear) }].compacted())
        }
    }
}

@MainActor
private struct RowPicker {

    private static let itemCount = 4 ... 20

    private let store: ItemStore
    private let token: ItemStore.RequestToken
    private var excluded: Set<TitleKey> = []

    // Begins before any request so newer user data is never overwritten
    init(store: ItemStore) throws {
        self.store = store
        self.token = try store.beginRequest()
    }

    mutating func exclude(_ items: [BaseItemDto]) {
        excluded.formUnion(items.flatMap(TitleKey.keys))
    }

    /// Picks unwatched titles first, skipping any already shown. Returns nil when too few are left to fill a row.
    mutating func row(id: String, title: String, from candidates: [ItemPatch]) throws -> HomeRecommendations.Row? {
        let (unwatched, watched) = candidates
            .filter { [.movie, .series].contains($0.value.type) }
            .partitioned { $0.value.userData?.isPlayed == true }

        var excluded = excluded
        var picked: [ItemPatch] = []

        for candidate in unwatched + watched where picked.count < Self.itemCount.upperBound {
            let keys = TitleKey.keys(for: candidate.value)
            guard excluded.isDisjoint(with: keys) else { continue }

            excluded.formUnion(keys)
            picked.append(candidate)
        }

        guard picked.count >= Self.itemCount.lowerBound else { return nil }

        self.excluded = excluded

        return try HomeRecommendations.Row(
            id: id,
            title: title,
            entries: picked.compactMap { try store.merge($0, token: token).map { ItemEntry(item: $0) } }
        )
    }
}

@MainActor
private struct Requests {

    let userSession: UserSession

    /// Movies and episodes the user played most recently, newest first
    func recentlyWatched() async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableImages = false
        parameters.enableUserData = true
        parameters.fields = [.genres]
        parameters.includeItemTypes = [.movie, .episode]
        parameters.isRecursive = true
        parameters.limit = 50
        parameters.sortBy = [.datePlayed]
        parameters.sortOrder = [.descending]
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getItems(parameters: parameters))

        return (response.value.items ?? []).filter { $0.userData?.lastPlayedDate != nil }
    }

    /// What Continue Watching and Next Up show, using the same queries as those rows
    func titlesOnHome() async throws -> [BaseItemDto] {
        let resumePage = try LibraryPageState(pageOffset: 0, pageSize: 50, userSession: userSession)
        let nextUpPage = try LibraryPageState(pageOffset: 0, pageSize: 50, userSession: userSession)

        async let resume = ResumeItemsLibrary().retrievePage(environment: .init(), pageState: resumePage)
        async let nextUp = NextUpLibrary().retrievePage(environment: .default, pageState: nextUpPage)

        return try await (resume + nextUp).map(\.value)
    }

    func movieRecommendations() async throws -> [MovieRecommendation] {
        var parameters = Paths.GetMovieRecommendationsParameters()
        parameters.categoryLimit = 8
        parameters.fields = PosterSubtitleField.itemFields
        parameters.itemLimit = 20
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getMovieRecommendations(parameters: parameters))

        // Patches come from the raw JSON so they keep which fields the server sent
        guard let objects = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]],
              objects.count == response.value.count
        else {
            throw CocoaError(.coderInvalidValue)
        }

        return try zip(response.value, objects).map { category, object in
            try MovieRecommendation(
                category: category,
                items: (category.items ?? []).patches(from: object["Items"] ?? [], scope: .partial)
            )
        }
    }

    func similar(to itemID: String) async throws -> [ItemPatch] {
        var parameters = Paths.GetSimilarItemsParameters()
        parameters.fields = PosterSubtitleField.itemFields
        parameters.limit = 30
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getSimilarItems(itemID: itemID, parameters: parameters))

        return try response.patches()
    }

    /// Unwatched movies and series in a genre, highest rated first
    func unwatched(genre: String) async throws -> [ItemPatch] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.filters = [.isUnplayed]
        parameters.genres = [genre]
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 40
        parameters.sortBy = [.communityRating, .sortName]
        parameters.sortOrder = [.descending, .ascending]
        parameters.userID = userSession.user.id

        let response = try await userSession.client.send(Paths.getItems(parameters: parameters))

        return try response.patches()
    }
}

/// A category from the server's movie recommendations, such as movies by a director the user recently watched
private struct MovieRecommendation {

    let category: RecommendationDto
    let items: [ItemPatch]

    var id: String {
        "recommendation-\(category.categoryID ?? category.baselineItemName ?? "")"
    }

    /// Lower sorts first. People rows add variety next to the similar-title rows above them.
    var priority: Int {
        switch category.recommendationType {
        case .hasDirectorFromRecentlyPlayed, .hasLikedDirector: 0
        case .hasActorFromRecentlyPlayed, .hasLikedActor: 1
        case .similarToLikedItem: 2
        case .similarToRecentlyPlayed, nil: 3
        }
    }

    var title: String? {
        guard let name = category.baselineItemName, let type = category.recommendationType else { return nil }

        return switch type {
        case .similarToRecentlyPlayed:
            L10n.becauseYouWatched(name)
        case .similarToLikedItem:
            L10n.becauseYouLiked(name)
        case .hasDirectorFromRecentlyPlayed, .hasLikedDirector:
            L10n.moreFromDirector(name)
        case .hasActorFromRecentlyPlayed, .hasLikedActor:
            L10n.starringActor(name)
        }
    }
}

private extension Array {

    /// Transforms every element at once, keeping their order
    func concurrentMap<T>(_ transform: @escaping (Element) async -> T) async -> [T] {
        await withTaskGroup(of: (Int, T).self) { group in
            for (index, element) in enumerated() {
                group.addTask { await (index, transform(element)) }
            }

            var results: [(index: Int, value: T)] = []

            for await result in group {
                results.append(result)
            }

            return results.sorted { $0.index < $1.index }.map(\.value)
        }
    }
}
