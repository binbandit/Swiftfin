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
            tag(L10n.newEpisodes)
                .padding(.leading, size * 2.5)

            tag(L10n.new)
        }
        .padding(size * 0.22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.newEpisodes)
    }

    private func tag(_ title: String) -> some View {
        Text(title.localizedUppercase)
            .font(.system(size: size * 0.42, weight: .bold))
            .kerning(0.5)
            .lineLimit(1)
            .foregroundStyle(accentColor.overlayColor)
            .padding(.horizontal, size * 0.26)
            .padding(.vertical, size * 0.12)
            .background(accentColor, in: .capsule)
            .shadow(color: .black.opacity(0.4), radius: size * 0.1, y: 1)
    }
}
