//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct AboutItemGroup: ContentGroup {

    let displayTitle: String
    let id: String
    @SharedBaseItem
    var item: BaseItemDto

    func body(with viewModel: Empty) -> Body {
        Body(item: item)
    }

    struct Body: View {

        @AdaptiveLayout
        private var viewLayout

        @Router
        private var router

        @SharedBaseItem
        var item: BaseItemDto

        private struct AboutCard<Content: View>: View {

            let title: String
            let subtitle: String?
            let action: () -> Void
            let content: Content

            init(
                title: String,
                subtitle: String? = nil,
                action: @escaping () -> Void,
                @ViewBuilder content: () -> Content
            ) {
                self.title = title
                self.subtitle = subtitle
                self.action = action
                self.content = content()
            }

            var body: some View {
                Button(action: action) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            if let subtitle, subtitle.isNotEmpty {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        content
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .backport
                    .glassEffect(
                        in: .rect(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                }
                .foregroundStyle(.primary, .secondary)
                .buttonStyle(.card)
                .buttonBorderShape(.roundedRectangle(radius: 20))
            }
        }

        @ViewBuilder
        private var descriptionCard: some View {
            let subtitle = item.taglines?.first ?? item.parentTitle
            let hasOverviewContent = item.taglines?.first?.isNotEmpty == true || item.overview?.isNotEmpty == true

            AboutCard(
                title: item.displayTitle,
                subtitle: subtitle
            ) {
                if hasOverviewContent {
                    router.route(to: .itemOverview(item: item))
                }
            } content: {
                if let overview = item.overview, overview.isNotEmpty {
                    SeeMoreText(overview)
                        .font(.footnote)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
        }

        @ViewBuilder
        private func mediaSourceCard(for mediaSource: MediaSourceInfo, hasMultipleSources: Bool) -> some View {
            let subtitle = hasMultipleSources ? mediaSource.displayTitle : nil

            AboutCard(
                title: L10n.media,
                subtitle: subtitle
            ) {
                router.route(to: .mediaSourceInfo(source: mediaSource))
            } content: {
                Grid(alignment: .leading, horizontalSpacing: gridColumnSpacing, verticalSpacing: 5) {
                    ForEach(streamSummary(for: mediaSource), id: \.label) { property in
                        GridRow {
                            Text(property.label)
                                .foregroundStyle(.secondary)

                            Text(property.value)
                                .lineLimit(1)
                        }
                    }
                }
                .font(.footnote)
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
        }

        /// One line each for video, audio, and subtitles, rather than every stream in server order
        @ArrayBuilder<MediaStream.Property>
        private func streamSummary(for mediaSource: MediaSourceInfo) -> [MediaStream.Property] {
            if let video = mediaSource.videoStreams?.first?.displayTitle {
                (label: L10n.video, value: video)
            }

            if let audioStreams = mediaSource.audioStreams,
               let audio = audioStreams.first(where: { $0.isDefault == true }) ?? audioStreams.first
            {
                let format = [audio.codec?.uppercased(), audio.channelLayout?.localizedCapitalized]
                    .compacted()
                    .joined(separator: " ")

                (label: L10n.audio, value: [languageName(for: audio), format.nilIfBlank].compacted().joined(separator: " · "))
            }

            if let subtitles = mediaSource.subtitleStreams?.compactMap(languageName(for:)).uniqued().joined(separator: ", "),
               subtitles.isNotEmpty
            {
                (label: L10n.subtitles, value: subtitles)
            }
        }

        private func languageName(for stream: MediaStream) -> String? {
            guard let language = stream.language, language != "und" else { return nil }

            return Locale.current.localizedString(forLanguageCode: language)
        }

        private func ratingsCard(criticRating: Float, communityRating: Float) -> some View {
            AboutCard(
                title: L10n.ratings,
                action: {}
            ) {
                // A grid keeps both scores aligned, whatever the width of each icon
                Grid(alignment: .leading, horizontalSpacing: gridColumnSpacing) {
                    if criticRating > -1 {
                        GridRow {
                            Group {
                                if criticRating >= 60 {
                                    Image(.tomatoFresh)
                                        .symbolRenderingMode(.multicolor)
                                        .foregroundStyle(.green, .red)
                                } else {
                                    Image(.tomatoRotten)
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(.green)
                                }
                            }
                            .font(.largeTitle)
                            .gridColumnAlignment(.center)

                            // swiftlint:disable:next hard_coded_display_string
                            Text("\(criticRating, specifier: "%.0f")")
                                .fontWeight(.semibold)
                        }
                    }

                    if communityRating > -1 {
                        GridRow {
                            Image(systemName: "star.fill")
                                .symbolRenderingMode(.multicolor)
                                .foregroundStyle(.yellow)
                                .font(.largeTitle)

                            // swiftlint:disable:next hard_coded_display_string
                            Text("\(communityRating, specifier: "%.1f")")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }

        private var gridColumnSpacing: CGFloat {
            viewLayout.value(standard: 12, large: 24)
        }

        private var cardHeight: CGFloat {
            viewLayout.value(standard: 200, large: 300)
        }

        private let cardAspectRatio: CGFloat = 1.77

        var body: some View {
            ContentGroupSection {
                ScrollView(.horizontal) {
                    HStack(spacing: viewLayout.itemSpacing) {
                        descriptionCard

                        if let mediaSources = item.mediaSources {
                            ForEach(mediaSources) { source in
                                mediaSourceCard(for: source, hasMultipleSources: mediaSources.count > 1)
                            }
                        }

                        if item.criticRating != nil || item.communityRating != nil {
                            ratingsCard(
                                criticRating: item.criticRating ?? -1,
                                communityRating: item.communityRating ?? -1
                            )
                        }
                    }
                    .edgePadding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .if(viewLayout.isLarge) { $0.withViewContext(.isOverComplexContent) }
                .frame(height: cardHeight)
                .frame(maxWidth: .infinity)
            } header: {
                Text(L10n.about)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .edgePadding(.horizontal)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.about)
        }
    }
}
