//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// Top Results, led by the best title match on a wide card, like the top hit in the Apple TV app.
///
/// The lead spans three columns of the portrait grid at poster height, so the results after it
/// line up with the rows below, and any title can lead without the row changing size.
struct TopResultsSection: View {

    /// As in the portrait rows of `PosterHStack`
    private static let columnCount: CGFloat = 7
    private static let leadColumnSpan: CGFloat = 3

    @AdaptiveLayout
    private var viewLayout

    @Router
    private var router

    @State
    private var scrollPosition = ScrollPosition(edge: .leading)
    @State
    private var width: CGFloat = 0

    @ObservedObject
    var viewModel: PagingLibraryViewModel<SearchContentGroupProvider.TopResultsLibrary>
    let displayTitle: String

    private var columnWidth: CGFloat {
        let gaps = viewLayout.itemSpacing * (Self.columnCount - 1)
        return max(0, (width - viewLayout.edgePadding * 2 - gaps) / Self.columnCount)
    }

    private var leadSize: CGSize {
        CGSize(
            width: columnWidth * Self.leadColumnSpan + viewLayout.itemSpacing * (Self.leadColumnSpan - 1),
            height: columnWidth * 3 / 2
        )
    }

    /// People have no wide artwork, so only a title leads.
    private var lead: ItemEntry? {
        guard let first = viewModel.elements.first, first.snapshot.type != .person else { return nil }

        return first
    }

    private var others: ArraySlice<ItemEntry> {
        viewModel.elements.elements.dropFirst(lead == nil ? 0 : 1)
    }

    private func select(_ entry: ItemEntry, in namespace: Namespace.ID) {
        entry.libraryDidSelectElement(router: router, in: namespace)
    }

    var body: some View {
        if viewModel.elements.isNotEmpty {
            ContentGroupSection {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: viewLayout.itemSpacing) {
                        if let lead {
                            TopResultLeadCard(entry: lead, artworkSize: leadSize) { namespace in
                                select(lead, in: namespace)
                            }
                        }

                        // Each place fades to its new result, like the lead, rather than results sliding past each other
                        ForEach(Array(others.enumerated()), id: \.offset) { _, entry in
                            ZStack {
                                PosterButton(item: entry, displayType: .portrait) { namespace in
                                    select(entry, in: namespace)
                                }
                                .id(entry.id)
                                .transition(.opacity)
                            }
                            .frame(width: columnWidth)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.elements.ids)
                }
                .contentMargins(.horizontal, viewLayout.edgePadding, for: .scrollContent)
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
                .scrollPosition($scrollPosition)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                // New results start from their best match, even if the last ones were scrolled through
                .onChange(of: viewModel.elements.ids) {
                    scrollPosition.scrollTo(edge: .leading)
                }
                .focusSection()
            } header: {
                Text(displayTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(displayTitle)
        }
    }
}

private struct TopResultLeadCard: View {

    /// The card's width in points, which image requests scale to the screen
    private static let imageWidth: CGFloat = 750

    @Namespace
    private var namespace

    let entry: ItemEntry
    let artworkSize: CGSize
    let action: (Namespace.ID) -> Void

    private var item: BaseItemDto {
        entry.snapshot
    }

    /// Backdrops carry no title, so they crop to the wide frame cleanly.
    private var artwork: some View {
        PosterImage(item: entry, type: .landscape, size: .custom(width: Self.imageWidth))
            .withViewContext(.isBackdrop)
            .frame(width: artworkSize.width, height: artworkSize.height)
            .clipped()
            .overlay { entry.posterOverlay(for: .landscape) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle)
                .font(.headline)

            DotHStack {
                if let type = item.type {
                    Text(type.displayTitle)
                }

                if let productionYear = item.productionYear {
                    Text(productionYear, format: .number.grouping(.never))
                }

                if let genre = item.genres?.first {
                    Text(genre)
                }

                if item.type == .movie, let runtime = item.runtime {
                    Text(runtime, format: .hourMinuteAbbreviated)
                }
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(width: artworkSize.width, alignment: .leading)
    }

    var body: some View {
        Button {
            action(namespace)
        } label: {
            // Swapped together, so a new top match fades in rather than jumping
            ZStack {
                artwork
                    .id(entry.id)
                    .transition(.opacity)
            }
            .contentShape(.contextMenuPreview, Rectangle())
            .matchedTransitionSource(id: "item", in: namespace)
            .subtleShadow()
            .hoverEffect(.highlight)
            .posterAccessibility(for: entry)

            ZStack(alignment: .topLeading) {
                details
                    .id(entry.id)
                    .transition(.opacity)
            }
            .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.3), value: entry.id)
        .environment(\.posterDisplayType, .landscape)
        .foregroundStyle(.primary, .secondary)
        .buttonStyle(.borderless)
        .buttonBorderShape(.roundedRectangle)
        .focusedValue(\.focusedPoster, AnyPoster(entry))
        .posterContextMenu(for: entry) {
            VStack(alignment: .leading) {
                artwork
                details
            }
            .posterAccessibility(for: entry)
            .padding(20)
            .backport
            .glassEffect(in: .rect(cornerRadius: 10))
        }
    }
}
