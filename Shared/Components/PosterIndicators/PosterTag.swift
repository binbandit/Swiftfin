//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// A short capsule label drawn over a poster's artwork, sized to match the poster indicators.
struct PosterTag: View {

    @AdaptiveLayout
    private var viewLayout

    let title: String
    let fill: Color
    let foreground: Color

    init(_ title: String, fill: Color, foreground: Color) {
        self.title = title
        self.fill = fill
        self.foreground = foreground
    }

    private var size: CGFloat {
        viewLayout.indicatorSize
    }

    var body: some View {
        Text(title.localizedUppercase)
            .font(.system(size: size * 0.42, weight: .bold))
            .kerning(0.5)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size * 0.26)
            .padding(.vertical, size * 0.12)
            .background(fill, in: .capsule)
            .shadow(color: .black.opacity(0.4), radius: size * 0.1, y: 1)
    }
}
