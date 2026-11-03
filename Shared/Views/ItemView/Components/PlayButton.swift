//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import Logging
import SwiftUI

struct PlayButton: View {

    @AdaptiveLayout
    private var viewLayout

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var provider: ItemContentGroupProvider

    @PlayMedia
    private var playMedia

    private var title: String {
        provider.playbackIntent?.item.playButtonLabel ?? L10n.play
    }

    private func play(fromBeginning: Bool = false) {
        guard var playbackIntent = provider.playbackIntent else {
            provider.logger.error("Play selected with no playback intent")
            return
        }

        if fromBeginning {
            playbackIntent.configuration.startSeconds = .zero
        }

        playMedia(intent: playbackIntent)
    }

    var body: some View {
        Button {
            play()
        } label: {
            Label(title, systemImage: "play.fill")
                .labelStyle(.leadingIcon)
                .controlSize(viewLayout.value(standard: .regular, large: .large))
                .lineLimit(1)
                .font(.callout)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .backport
                .glassEffect(
                    .regular.selection(
                        tint: accentColor,
                        foregroundColor: accentColor.overlayColor
                    ),
                    in: .capsule
                )
        }
        .buttonBorderShape(.capsule)
        .buttonStyle(BasicHoverButtonStyle())
        .accessibilityLabel(L10n.play)
        .accessibilityValue([title, provider.playbackIntent?.item.timeLeftLabel].compacted().joined(separator: ", "))
        .contextMenu {
            if (provider.playbackIntent?.item.userData?.playbackPositionTicks ?? 0) > 0 {
                Button(L10n.playFromBeginning, systemImage: "gobackward") {
                    play(fromBeginning: true)
                }
            }
        }
        .disabled(provider.playbackIntent == nil)
    }
}

extension PlayButton {

    /// Resume progress and the selected version, kept outside the button so its label stays on one line
    struct Details: View {

        @AdaptiveLayout
        private var viewLayout

        @Default(.accentColor)
        private var accentColor

        @ObservedObject
        var provider: ItemContentGroupProvider

        private var resumeProgress: (fraction: Double, timeLeft: String)? {
            guard let item = provider.playbackIntent?.item,
                  let timeLeft = item.timeLeftLabel,
                  let fraction = item.progressPercentage
            else { return nil }

            return (fraction, timeLeft)
        }

        private var mediaSource: String? {
            guard provider.playbackIntent?.item.mediaSources?.count ?? 0 > 1 else { return nil }

            return provider.playbackIntent?.mediaSource?.displayTitle
        }

        var body: some View {
            if resumeProgress != nil || mediaSource != nil {
                VStack(alignment: .leading, spacing: viewLayout.value(standard: 2, large: 4)) {
                    if let resumeProgress {
                        HStack(spacing: viewLayout.value(standard: 8, large: 16)) {
                            ProgressView(value: resumeProgress.fraction)
                                .progressViewStyle(.playback)
                                .foregroundStyle(accentColor)
                                .frame(height: viewLayout.value(standard: 4, large: 6))
                                .accessibilityHidden(true)

                            Text(resumeProgress.timeLeft)
                                .monospacedDigit()
                        }
                    }

                    if let mediaSource {
                        Marquee(mediaSource, speed: 40, delay: 3, fade: 5)
                    }
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension BaseItemDto {

    /// Time remaining in a partly watched item, such as "4m left", matching the poster progress badges
    var timeLeftLabel: String? {
        guard currentProgram == nil, (userData?.playbackPositionTicks ?? 0) > 0, let progressLabel else { return nil }

        return L10n.durationLeft(progressLabel)
    }
}
