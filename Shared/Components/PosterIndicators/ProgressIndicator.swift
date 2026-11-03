//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Draws progress along the bottom of a poster. Landscape cards list the remaining time in their label instead,
/// so no text covers the artwork.
struct ProgressIndicator: View {

    @AdaptiveLayout
    private var viewLayout

    @Default(.accentColor)
    private var accentColor

    let progress: Double
    let posterDisplayType: PosterDisplayType

    private let indicators: [QuadrantItem]

    init(
        progress: Double,
        posterDisplayType: PosterDisplayType,
        @ArrayBuilder<QuadrantItem> indicators: () -> [QuadrantItem]
    ) {
        self.progress = progress
        self.posterDisplayType = posterDisplayType
        self.indicators = indicators()
    }

    private var inset: CGFloat {
        viewLayout.value(standard: 6, large: 10)
    }

    private var normalizedProgress: Double {
        progress.isFinite ? clamp(progress, min: 0, max: 1) : 0
    }

    private var progressBar: some View {
        ProgressView(value: normalizedProgress)
            .progressViewStyle(.playback)
            .foregroundStyle(accentColor)
            .frame(height: 6)
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .accessibilityHidden(true)
    }

    private var compactProgressBar: some View {
        Rectangle()
            .fill(accentColor)
            .scaleEffect(x: normalizedProgress, y: 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 6)
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: inset) {
            if indicators.isNotEmpty {
                Quadrant(.bottomTrailing, isFloating: true) {
                    indicators
                }
                .padding(.horizontal, inset)
            }

            // Badges sit above the bar so it can span the poster.
            if posterDisplayType == .landscape {
                progressBar
            } else {
                compactProgressBar
            }
        }
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .colorScheme(.dark)
    }
}
