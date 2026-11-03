//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Heads a tab's library with its filter bar.
///
/// Presented libraries show the bar under their title instead, through `PagingLibrary.makeHeaderAccessory()`.
struct FilterBarModifier: ViewModifier {

    @AdaptiveLayout
    private var viewLayout

    @Environment(\.isPresented)
    private var isPresented

    @ObservedObject
    var viewModel: FilterViewModel

    let types: [ItemFilterType]

    func body(content: Content) -> some View {
        if types.isEmpty || isPresented {
            content
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Library grids inset their items by the edge padding, so the bar lines up with them.
                    LibraryFilterBar(viewModel: viewModel, types: types)
                        .contentMargins(.horizontal, viewLayout.edgePadding, for: .scrollContent)
                        .padding(.top, viewLayout.itemSpacing / 2)
                }
        }
    }
}

/// A library's filter bar, with room below it for a focused poster in the first row
struct LibraryFilterBar: View {

    @AdaptiveLayout
    private var viewLayout

    let viewModel: FilterViewModel
    let types: [ItemFilterType]

    var body: some View {
        if types.isNotEmpty {
            FilterBar(viewModel: viewModel, types: types)
                .padding(.bottom, viewLayout.itemSpacing / 2)
                .coordinatedFocus(.secondary)
        }
    }
}
