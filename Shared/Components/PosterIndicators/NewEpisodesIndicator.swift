//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// A tag in the unplayed indicator's corner for series that gained episodes since the user last watched them.
struct NewEpisodesIndicator: View {

    @AdaptiveLayout
    private var viewLayout

    @Default(.accentColor)
    private var accentColor

    private var size: CGFloat {
        viewLayout.indicatorSize
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // The full label only where most of the artwork stays clear beside it
            PosterTag(L10n.newEpisodes, fill: accentColor, foreground: accentColor.overlayColor)
                .padding(.leading, size * 2.5)

            PosterTag(L10n.new, fill: accentColor, foreground: accentColor.overlayColor)
        }
        .padding(size * 0.22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.newEpisodes)
    }
}
