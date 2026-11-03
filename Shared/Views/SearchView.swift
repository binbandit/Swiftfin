//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct SearchView: View {

    @AdaptiveLayout
    private var viewLayout

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters

    @FocusState
    private var isSearchFocused: Bool

    @State
    private var searchQuery = ""

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel = SearchViewModel()

    @TabItemSelected
    private var tabItemSelected

    private var suggestionsView: some View {
        VStack(spacing: 20) {
            ForEach(viewModel.suggestions) { item in
                Button(item.displayTitle) {
                    searchQuery = item.displayTitle
                }
                #if os(tvOS)
                .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .multilineTextAlignment(.center)
    }

    private var noResultsView: some View {
        let query = viewModel.filterViewModel.currentFilters.query

        return ContentUnavailableView {
            Label(
                query.map { L10n.noResultsForQuery($0) } ?? L10n.noResults.localizedCapitalized,
                systemImage: "magnifyingglass"
            )
        } description: {
            Text(viewModel.filterViewModel.hasActiveFilters ? L10n.searchFiltersHint : L10n.searchNoResultsHint)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(tvOS)
                if enabledDrawerFilters.isNotEmpty {
                    FilterBar(viewModel: viewModel.filterViewModel, types: enabledDrawerFilters)
                        .contentMargins(.horizontal, viewLayout.edgePadding, for: .scrollContent)
                        .padding(.vertical, viewLayout.itemSpacing)
                }
                #endif

                ZStack {
                    switch viewModel.state {
                    case .error:
                        viewModel.error.map(ErrorView.init)

                    case .initial, .searching:
                        if !viewModel.canSearch {
                            suggestionsView
                        } else if viewModel.isNotEmpty {
                            // Keep the current results in place while the next ones load.
                            ContentGroupVStack(groups: viewModel.groups)
                        } else if viewModel.state == .searching {
                            ProgressView()
                        } else {
                            noResultsView
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .focusSection()
            }
        }
        .ignoresSafeArea(edges: viewLayout.scrollContentEdges(extendsTop: false))
        .defaultScrollAnchor(viewModel.canSearch ? .top : .center, for: .alignment)
        .scrollIndicators(.hidden)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(L10n.search)
        .toolbarTitleDisplayMode(.inline)
        .searchFocused($isSearchFocused)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
        .onFirstAppear {
            viewModel.getSuggestions()
        }
        .onChange(of: searchQuery) {
            viewModel.search(query: searchQuery)
        }
        .searchable(
            text: $searchQuery,
            prompt: L10n.search
        )
        .environmentObject(focusCoordinator)
        #if os(tvOS)
        .modifier(SearchSafeAreaModifier())
        #endif
        #if os(iOS)
        .navigationBarFilterDrawer(
            viewModel: viewModel.filterViewModel,
            types: enabledDrawerFilters
        )
        #endif
    }
}
