//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import SwiftUI

extension SeriesEpisodeContentGroup {

    private enum EpisodeElement: Identifiable {

        case empty
        case episode(ItemEntry)
        case error(Error)
        case loading(Int)

        static var loadingElements: [Self] {
            (0 ..< 10).map { .loading($0) }
        }

        var id: String {
            switch self {
            case .empty:
                "empty"
            case let .episode(episode):
                episode.itemID
            case .error:
                "error"
            case let .loading(index):
                "loading-\(index)"
            }
        }
    }

    struct LoadingEpisodesView<Header: View>: View {

        let header: Header

        init(@ViewBuilder header: () -> Header) {
            self.header = header()
        }

        var body: some View {
            EpisodeCollectionLayout(
                elements: EpisodeElement.loadingElements,
                preferredElementID: EpisodeElement.loadingElements.first?.id
            ) {
                header
            } content: { element in
                EpisodeElementCard(element: element, refresh: {})
            }
            .scrollDisabled(true)
        }
    }

    struct SeasonEpisodesView<Header: View>: View {

        @ObservedObject
        var seasonViewModel: PagingLibraryViewModel<EpisodeLibrary>

        @OptionalSharedBaseItem
        var playButtonItem: BaseItemDto?
        let excludedEpisodeID: String?
        let header: Header

        init(
            seasonViewModel: PagingLibraryViewModel<EpisodeLibrary>,
            playButtonItem: BaseItemDto?,
            excludedEpisodeID: String?,
            @ViewBuilder header: () -> Header
        ) {
            self.seasonViewModel = seasonViewModel
            self.playButtonItem = playButtonItem
            self.excludedEpisodeID = excludedEpisodeID
            self.header = header()
        }

        private var episodes: [ItemEntry] {
            seasonViewModel.elements.filter { $0.itemID != excludedEpisodeID }
        }

        /// The episode after the excluded one, or the one before it when the excluded episode ends the season
        private var excludedEpisodeNeighborID: String? {
            let elements = seasonViewModel.elements

            guard let index = elements.firstIndex(where: { $0.itemID == excludedEpisodeID }) else { return nil }

            return (elements[safe: index + 1] ?? elements[safe: index - 1])?.itemID
        }

        /// An episode's own page has nothing to list when its season holds no other episodes
        private var isEmptyWithoutExcludedEpisode: Bool {
            excludedEpisodeID != nil && seasonViewModel.state == .content && episodes.isEmpty
        }

        private var elements: [EpisodeElement] {
            switch seasonViewModel.state {
            case .content:
                if episodes.isEmpty {
                    [.empty]
                } else {
                    episodes.map(EpisodeElement.episode)
                }

            case .error:
                [seasonViewModel.error.map(EpisodeElement.error) ?? .error(ErrorMessage(L10n.unknownError))]

            case .initial, .refreshing:
                EpisodeElement.loadingElements
            }
        }

        private var preferredElementID: EpisodeElement.ID? {
            if let playButtonItemID = playButtonItem?.id,
               elements.contains(where: { $0.id == playButtonItemID })
            {
                return playButtonItemID
            }

            return excludedEpisodeNeighborID ?? elements.first?.id
        }

        var body: some View {
            if !isEmptyWithoutExcludedEpisode {
                EpisodeCollectionLayout(
                    elements: elements,
                    preferredElementID: preferredElementID
                ) {
                    header
                } content: { element in
                    EpisodeElementCard(element: element) {
                        seasonViewModel.refresh()
                    }
                }
                .scrollDisabled(seasonViewModel.state != .content)
            }
        }
    }

    private struct EpisodeCollectionLayout<Header: View, Content: View>: View {

        @AdaptiveLayout
        private var viewLayout

        private enum FocusedSection: Hashable {

            case seasons
            case episodes
        }

        @FocusState
        private var focusedSection: FocusedSection?
        @FocusState
        private var focusedElement: EpisodeElement.ID?

        let elements: [EpisodeElement]
        let preferredElementID: EpisodeElement.ID?
        let header: Header
        let content: (EpisodeElement) -> Content

        init(
            elements: [EpisodeElement],
            preferredElementID: EpisodeElement.ID?,
            @ViewBuilder header: () -> Header,
            @ViewBuilder content: @escaping (EpisodeElement) -> Content
        ) {
            self.elements = elements
            self.preferredElementID = preferredElementID
            self.header = header()
            self.content = content
        }

        private var layout: CollectionHStackLayout {
            .minimumWidth(
                columnWidth: viewLayout.posterMinimumWidth(for: .landscape, size: .medium),
                rows: 1,
                columnFraction: 0.5
            )
        }

        var body: some View {
            ContentGroupSection {
                CollectionHStack(
                    uniqueElements: elements,
                    layout: layout
                ) { element in
                    content(element)
                        .focused($focusedElement, equals: element.id)
                }
                .initialElement(id: preferredElementID)
                .clipsToBounds(false)
                .insets(horizontal: viewLayout.edgePadding)
                .itemSpacing(viewLayout.itemSpacing)
                .scrollBehavior(.continuousLeadingEdge)
                #if os(iOS)
                .contentInsetAdjustmentBehavior(.never)
                #endif
                .focusSection()
                .focused($focusedSection, equals: .episodes)
                .defaultFocus(
                    $focusedElement,
                    preferredElementID,
                    priority: .userInitiated
                )
            } header: {
                header
                    .focusSection()
                    .focused($focusedSection, equals: .seasons)
            }
            .focusSection()
            .defaultFocus(
                $focusedSection,
                .episodes,
                priority: .userInitiated
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.seasons)
        }
    }

    private struct EpisodeElementCard: View {

        let element: EpisodeElement
        let refresh: () -> Void

        var body: some View {
            switch element {
            case .empty:
                EpisodeStateCard(
                    title: L10n.noResults,
                    subHeader: .emptyDash,
                    content: L10n.noEpisodesAvailable,
                    systemImage: nil,
                    action: {}
                )
                .disabled(true)

            case let .episode(episode):
                EpisodeCard(episode: episode.snapshot)

            case let .error(error):
                EpisodeStateCard(
                    title: L10n.error,
                    subHeader: .emptyDash,
                    content: error.localizedDescription,
                    systemImage: "arrow.clockwise",
                    action: refresh
                )

            case .loading:
                EpisodeStateCard(
                    title: String.random(count: 10 ..< 20),
                    subHeader: String.random(count: 7 ..< 12),
                    content: String.random(count: 20 ..< 80),
                    systemImage: nil,
                    action: {}
                )
                .redacted(reason: .placeholder)
                .disabled(true)
            }
        }
    }
}
