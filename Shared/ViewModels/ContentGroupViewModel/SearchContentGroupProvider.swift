//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

@MainActor
struct SearchContentGroupProvider: ContentGroupProvider {

    struct Environment: WithDefaultValue {
        var filters: ItemFilterCollection

        static var `default`: Self {
            .init(filters: .init())
        }
    }

    private static let itemTypes: [BaseItemKind] = [
        .movie,
        .series,
        .boxSet,
        .episode,
        .musicVideo,
        .video,
        .liveTvProgram,
        .tvChannel,
        .musicArtist,
    ]

    let id: String = UUID().uuidString
    let displayTitle: String = L10n.search
    let filterViewModel: FilterViewModel
    var environment: Environment

    init() {
        let filterViewModel: FilterViewModel = .init()

        self.filterViewModel = filterViewModel
        self.environment = .init(filters: filterViewModel.currentFilters)
    }

    @ContentGroupBuilder
    func makeGroups(environment: Environment) async throws -> [any ContentGroup] {
        if let query = environment.filters.query {
            TopResultsGroup(library: TopResultsLibrary(query: query, filters: environment.filters))
        }

        try await ItemTypeContentGroupProvider(itemTypes: Self.itemTypes)
            .makeGroups(environment: .init(filters: environment.filters))

        PosterGroup(
            library: PeopleLibrary(
                environment: .init(query: environment.filters.query)
            )
        )
    }
}

extension SearchContentGroupProvider {

    /// Top Results, which tvOS leads with the best match
    struct TopResultsGroup: ContentGroup {

        let id = "search-top-results"

        private let group: PosterGroup<TopResultsLibrary>

        var viewModel: PagingLibraryViewModel<TopResultsLibrary> {
            group.viewModel
        }

        var _shouldBeResolved: Bool {
            group._shouldBeResolved
        }

        init(library: TopResultsLibrary) {
            self.group = PosterGroup(
                id: id,
                library: library,
                environment: .init(isHeaderButtonEnabled: false)
            )
        }

        func body(with viewModel: PagingLibraryViewModel<TopResultsLibrary>) -> some View {
            #if os(tvOS)
            TopResultsSection(viewModel: viewModel, displayTitle: group.displayTitle)
            #else
            group.body(with: viewModel)
            #endif
        }
    }

    /// The strongest name matches among shows, movies, collections, and people
    struct TopResultsLibrary: MediaLibrary {

        private static let limit = 10
        private static let peopleLimit = 2

        let hasNextPage = false
        let parent: TitledLibraryParent = .init(displayTitle: L10n.topResults, id: "search-top-results")

        private let library: ItemLibrary
        private let people: PeopleLibrary
        private let query: String

        init(query: String, filters: ItemFilterCollection) {
            var filters = filters
            filters.itemTypes = [.movie, .series, .boxSet]

            // Without a sort the server orders by relevance, which the ranking below refines.
            filters.sortBy = []
            filters.sortOrder = []

            self.library = ItemLibrary(parent: BaseItemDto(), filters: filters)
            self.people = PeopleLibrary(environment: .init(query: query))
            self.query = Self.normalized(query)
        }

        func retrievePage(
            environment: Empty,
            pageState: LibraryPageState
        ) async throws -> [ItemPatch] {
            let titles = try await library.retrievePage(
                environment: library.environment ?? .default,
                pageState: pageState
            )
            let persons = try await people.retrievePage(
                environment: people.environment ?? .default,
                pageState: pageState
            )

            // Titles lead, and a couple of people follow them.
            let results = ranked(titles) + ranked(persons).prefix(Self.peopleLimit)

            return Array(results.prefix(Self.limit))
        }

        /// Keeps the strong matches, best first, with the server's order breaking ties
        private func ranked(_ page: [ItemPatch]) -> [ItemPatch] {
            page.enumerated()
                .compactMap { offset, patch in
                    match(for: patch.value).map { (rank: ($0, offset), patch: patch) }
                }
                .sorted { $0.rank < $1.rank }
                .map(\.patch)
        }

        /// Ranks an exact name first, then a name that starts with the query, then a name with a word that does.
        ///
        /// - Returns: `nil` for weaker matches, which stay in their own rows.
        private func match(for item: BaseItemDto) -> Int? {
            let name = Self.normalized(item.name ?? "")

            if name == query {
                return 0
            } else if name.hasPrefix(query) {
                return 1
            } else if name.contains(" \(query)") {
                return 2
            } else {
                return nil
            }
        }

        /// Folds case and diacritics, and collapses punctuation into single spaces
        private static func normalized(_ string: String) -> String {
            string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
        }
    }
}
