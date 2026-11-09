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
    /// The episode whose page shows this group. The row opens on it and marks it, and takes a heading instead of a season picker
    let currentEpisodeID: String?
    let viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    init(
        parent: BaseItemDto,
        playButtonItem: BaseItemDto? = nil,
        currentEpisodeID: String? = nil
    ) {
        self.id = "\(parent.id ?? "parent")-episode-selector"
        self.playButtonItem = playButtonItem
        self.currentEpisodeID = currentEpisodeID
        self.viewModel = .init(library: SeasonViewModelLibrary(parent: parent), pageSize: 100)
    }

    func body(with viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>) -> Body {
        Body(
            viewModel: viewModel,
            playButtonItem: playButtonItem,
            currentEpisodeID: currentEpisodeID
        )
    }

    struct Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        @OptionalSharedBaseItem
        var playButtonItem: BaseItemDto?
        let currentEpisodeID: String?

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?

        private var selectedSeasonViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            viewModel.elements.first { $0.id == selection }
        }

        @ViewBuilder
        private var header: some View {
            if currentEpisodeID != nil, let season = viewModel.elements.first {
                // An episode's page shows only its own season, so a picker would offer a single choice
                Text(season.library.parent.displayTitle)
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
                        currentEpisodeID: currentEpisodeID
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
