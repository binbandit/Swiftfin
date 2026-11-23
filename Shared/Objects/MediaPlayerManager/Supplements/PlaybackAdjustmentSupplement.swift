//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@MainActor
struct PlaybackAdjustmentSupplement {

    let id: String
    let displayTitle: String
    let value: (MediaSession) -> Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let shortcuts: [PlaybackAdjustmentSlider.Shortcut]
    let resetValue: Double
    let formatValue: (Double) -> String

    var preferredFocusID: String {
        "\(VideoPlayer.ViewState.Focus.supplementContent(id)).slider"
    }
}

extension PlaybackAdjustmentSupplement: VideoPlayerSupplement {

    var body: some View {
        AdjustmentView(supplement: self)
    }

    private struct AdjustmentView: PresentationView {

        @AdaptiveLayout
        private var viewLayout

        @Environment(VideoPlayer.ViewState.self)
        private var viewState

        @Environment(MediaSession.self)
        private var mediaSession

        let supplement: PlaybackAdjustmentSupplement

        private var content: some View {
            PlaybackAdjustmentSlider(
                value: supplement.value(mediaSession),
                title: supplement.displayTitle,
                range: supplement.range,
                step: supplement.step,
                shortcuts: supplement.shortcuts,
                resetValue: supplement.resetValue,
                formatValue: supplement.formatValue,
                focusID: supplement.preferredFocusID
            )
            .frame(maxWidth: viewLayout.isLarge ? 1200 : 700)
            .frame(maxWidth: .infinity)
            .edgePadding(.horizontal)
            .padding(.vertical, viewLayout.isLarge ? 24 : 12)
            .padding(.leading, viewState.supplementInsets.leading)
            .padding(.trailing, viewState.supplementInsets.trailing)
            .scrollIfLargerThanContainer()
            .padding(.bottom, viewState.supplementInsets.bottom)
        }

        var standardView: some View {
            content
        }

        var largeView: some View {
            content
                .focusSection()
        }
    }
}

extension PlaybackAdjustmentSupplement {

    static var audioOffset: Self {
        offset(
            id: "PlaybackAdjustment-audioOffset",
            title: L10n.audioOffset,
            keyPath: \.audioOffset,
            range: -5000 ... 5000,
            step: 50
        )
    }

    static var subtitleOffset: Self {
        offset(
            id: "PlaybackAdjustment-subtitleOffset",
            title: L10n.subtitleOffset,
            keyPath: \.subtitleOffset,
            range: subtitleOffsetRange,
            step: subtitleOffsetStep
        )
    }

    static var secondarySubtitleOffset: Self {
        offset(
            id: "PlaybackAdjustment-secondarySubtitleOffset",
            title: L10n.secondarySubtitleOffset,
            keyPath: \.secondarySubtitleOffset,
            range: subtitleOffsetRange,
            step: subtitleOffsetStep
        )
    }

    // Subtitles timed for a different release can be out by many seconds, such as when an intro is cut,
    // so they reach further than audio, without needing audio's lip-sync precision.
    private static let subtitleOffsetRange: ClosedRange<Double> = -15000 ... 15000
    private static let subtitleOffsetStep: Double = 100

    static func playbackSpeed(range: ClosedRange<Double>) -> Self {
        Self(
            id: "PlaybackAdjustment-speed",
            displayTitle: L10n.playbackSpeed,
            value: { mediaSession in
                Binding(get: { mediaSession.effectiveRate }, set: { mediaSession.rate = $0 })
            },
            range: range,
            step: 0.05,
            shortcuts: [0.5, 0.75, 1, 1.25, 1.5, 2].map { speed in
                .init(title: speed == 1 ? L10n.reset : speed.formatted(.playbackRate(precision: 2)), action: .set(speed))
            },
            resetValue: 1,
            formatValue: { $0.formatted(.playbackRate(precision: 2)) }
        )
    }

    private static func offset(
        id: String,
        title: String,
        keyPath: ReferenceWritableKeyPath<MediaPlayerItem, Duration>,
        range: ClosedRange<Double>,
        step: Double
    ) -> Self {
        Self(
            id: id,
            displayTitle: title,
            value: { mediaSession in
                Binding(
                    get: { Double((mediaSession.playbackItem?[keyPath: keyPath] ?? .zero).microseconds) / 1000 },
                    set: { mediaSession.playbackItem?[keyPath: keyPath] = .milliseconds(Int64($0.rounded())) }
                )
            },
            range: range,
            step: step,
            // Each press moves the offset again, so it can be walked in fine or coarse steps
            shortcuts: [-1000, -500, -100].map(offsetAdjustment)
                + [.init(title: L10n.reset, action: .set(0))]
                + [100, 500, 1000].map(offsetAdjustment),
            resetValue: 0,
            formatValue: { value in
                Duration.milliseconds(Int64(value.rounded()))
                    .formatted(.playbackOffset)
            }
        )
    }

    /// A signed, compact label such as "+0.5s", which keeps the row of shortcuts on one line
    private static func offsetAdjustment(by milliseconds: Double) -> PlaybackAdjustmentSlider.Shortcut {
        let label = Duration.milliseconds(Int64(milliseconds)).formatted(
            .units(
                allowed: [.seconds],
                width: .narrow,
                fractionalPart: milliseconds.truncatingRemainder(dividingBy: 1000) == 0 ? .hide : .show(length: 1)
            )
        )

        return .init(title: milliseconds > 0 ? "+\(label)" : label, action: .adjust(by: milliseconds))
    }
}
