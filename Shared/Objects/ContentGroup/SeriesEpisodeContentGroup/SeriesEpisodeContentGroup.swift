//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: when used for single seasons, have title as just "Episodes" or
//       have functionality in PosterGroup

struct SeriesEpisodeContentGroup: ContentGroup, Identifiable {

    let id: String
    @OptionalSharedBaseItem
    var playButtonItem: BaseItemDto?
    /// The episode whose page shows this group. It is left out, and the row takes a heading instead of a season picker
    let excludedEpisodeID: String?
    let viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    init(
        parent: BaseItemDto,
        playButtonItem: BaseItemDto? = nil,
        excludedEpisodeID: String? = nil
    ) {
        self.id = "\(parent.id ?? "parent")-episode-selector"
        self.playButtonItem = playButtonItem
        self.excludedEpisodeID = excludedEpisodeID
        self.viewModel = .init(library: SeasonViewModelLibrary(parent: parent), pageSize: 100)
    }

    func body(with viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>) -> Body {
        Body(
            viewModel: viewModel,
            playButtonItem: playButtonItem,
            excludedEpisodeID: excludedEpisodeID
        )
    }

    struct Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        @OptionalSharedBaseItem
        var playButtonItem: BaseItemDto?
        let excludedEpisodeID: String?

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?

        private var selectedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            viewModel.elements.first { $0.id == selection }
        }

        @ViewBuilder
        private var header: some View {
            if excludedEpisodeID != nil, let season = viewModel.elements.first {
                // An episode's page shows only its own season, so a picker would offer a single choice
                Text(L10n.moreFromSeason(season.library.parent.displayTitle))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .edgePadding(.horizontal)
            } else {
                SeasonSelector(
                    selection: $selection,
                    seasons: Array(viewModel.elements),
                    preferredSelection: selection ?? preferredSeasonSelection()
                )
            }
        }

        private func preferredSeasonSelection() -> PagingLibraryViewModel<EpisodeLibrary>.ID? {
            if let playButtonSeasonID = playButtonItem?.seasonID,
               viewModel.elements.contains(where: { $0.id == playButtonSeasonID })
            {
                return playButtonSeasonID
            }

            return viewModel.elements.first?.id
        }

        private func selectPreferredSeasonIfNeeded() {
            if selection == nil || !viewModel.elements.contains(where: { $0.id == selection }) {
                selection = preferredSeasonSelection()
            }
        }

        private func refreshSelectedSeasonIfNeeded() {
            guard let selectedSeasonViewModel, selectedSeasonViewModel.state == .initial else { return }

            selectedSeasonViewModel.refresh()
        }

        var body: some View {
            Group {
                if let selectedSeasonViewModel {
                    SeasonEpisodesView(
                        seasonViewModel: selectedSeasonViewModel,
                        playButtonItem: playButtonItem,
                        excludedEpisodeID: excludedEpisodeID
                    ) {
                        header
                    }
                } else {
                    LoadingEpisodesView {
                        header
                    }
                }
            }
            .onFirstAppear {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: viewModel.elements.map(ObjectIdentifier.init)) {
                selectPreferredSeasonIfNeeded()
                refreshSelectedSeasonIfNeeded()
            }
            .onChange(of: selection) {
                refreshSelectedSeasonIfNeeded()
            }
        }
    }
}
