//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct BaseItemDtoPosterLabel: View {

    @Environment(\.posterConfiguration)
    private var posterConfiguration
    @Environment(\.posterDisplayType)
    private var posterDisplayType

    @SharedBaseItem
    var item: BaseItemDto

    private var isTitlePresented: Bool {
        switch item.type {
        case .audio, .audioBook, .book, .boxSet, .episode, .liveTvProgram, .movie, .musicAlbum, .musicVideo,
             .photo, .photoAlbum, .playlist, .program, .recording, .season, .series, .trailer, .tvProgram, .video:
            posterConfiguration.isTitlePresented
        default:
            true
        }
    }

    private var episodeLocator: String? {
        guard item.type == .episode else { return nil }

        return item.seasonEpisodeLabel ?? item.episodeLocator
    }

    /// The item's own title, listed below an artwork title such as its series.
    /// A card being resumed lists its time left instead, keeping the line short.
    private var itemTitle: String? {
        guard isTitlePresented, item.artworkTitle != item.displayTitle, remainingTime == nil else { return nil }

        return item.displayTitle
    }

    private var subtitle: String? {
        guard let subtitle = item.posterSubtitle(using: posterConfiguration.subtitleField),
              item.extraType != nil || subtitle != item.displayTitle else { return nil }

        return subtitle
    }

    /// Landscape cards list the time left here instead of over their artwork.
    private var remainingTime: String? {
        guard posterDisplayType == .landscape,
              posterConfiguration.indicators.contains(.progress),
              let runtime = item.runtime,
              let position = item.startSeconds,
              position > .zero, position < runtime else { return nil }

        return (runtime - position).formatted(.timeLeft)
    }

    private var isProgram: Bool {
        item.type == .program || item.type == .liveTvProgram || item.type == .tvProgram
    }

    private var hasSubtitle: Bool {
        isProgram || episodeLocator != nil || itemTitle != nil || subtitle != nil || remainingTime != nil
    }

    @ViewBuilder
    private var programSchedule: some View {
        if let startDate = item.startDate {
            ViewThatFits {
                SeparatorHStack {
                    Text(String.hyphen)
                } content: {
                    programStartDate(startDate)

                    if let endDate = item.endDate {
                        Text(endDate, style: .time)
                    }
                }

                programStartDate(startDate)
            }
        } else {
            Text(String.emptyRuntime)
        }
    }

    @ViewBuilder
    private func programStartDate(_ date: Date) -> some View {
        if Calendar.current.isDateInToday(date) {
            Text(date, style: .time)
        } else {
            Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        if isProgram {
            DotHStack {
                programSchedule
                    .layoutPriority(1)

                if posterDisplayType == .landscape, let channelName = item.channelName {
                    Text(channelName)
                }
            }
        } else if hasSubtitle {
            DotHStack {
                if let episodeLocator {
                    Text(episodeLocator)
                        .fixedSize()
                        .layoutPriority(1)
                }

                if let itemTitle {
                    Text(itemTitle)
                }

                if let subtitle {
                    Text(subtitle)
                }

                if let remainingTime {
                    Text(remainingTime)
                        .layoutPriority(1)
                }
            }
        }
    }

    var body: some View {
        AlternateLayoutView(alignment: .topLeading) {
            VStack(spacing: 2) {
                Text(String.space)
                Text(String.space)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        } content: {
            if isTitlePresented || hasSubtitle {
                VStack(alignment: .leading, spacing: 2) {
                    if isTitlePresented {
                        Text(item.artworkTitle)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                            .lineLimit(hasSubtitle ? 1 : 2, reservesSpace: true)
                    }

                    subtitleView
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
