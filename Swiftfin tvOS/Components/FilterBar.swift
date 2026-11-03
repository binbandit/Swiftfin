//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// A "Filter & Sort" menu, the current sort, and a chip for each active filter. Selecting a chip clears its filter.
struct FilterBar: View {

    private enum FocusTarget: Hashable {
        case menu
        case sort
        case chip(ItemFilterType)
    }

    @Default(.accentColor)
    private var accentColor

    @FocusState
    private var focusedTarget: FocusTarget?

    @Router
    private var router

    @ObservedObject
    var viewModel: FilterViewModel

    let types: [ItemFilterType]

    private var filterTypes: [ItemFilterType] {
        types.filter { $0 != .sortBy }
    }

    private var activeTypes: [ItemFilterType] {
        filterTypes.filter { viewModel.isFilterSelected(type: $0) }
    }

    /// The sort field and its direction, such as "Name, A to Z"
    private var sortSummary: String {
        guard let sortBy = viewModel.currentFilters.sortBy.first else { return "" }

        let order = viewModel.currentFilters.sortOrder.first.flatMap(sortBy.orderTitle)

        return [sortBy.displayTitle, order].compactMap(\.self).joined(separator: ", ")
    }

    /// The first few selected values, in the order of the filter's options, then a count of the rest
    private func summary(for type: ItemFilterType, showing limit: Int = 2) -> String {
        let values = type.group.flatMap { group in
            let options = viewModel.allFilters[keyPath: group.keyPath]

            return viewModel.currentFilters[keyPath: group.keyPath]
                .sorted { (options.firstIndex(of: $0) ?? .max) < (options.firstIndex(of: $1) ?? .max) }
        }

        let titles = values.prefix(limit).map(\.displayTitle).joined(separator: ", ")

        return values.count > limit ? "\(titles) +\(values.count - limit)" : titles
    }

    private func route(to type: ItemFilterType, from target: FocusTarget) {
        router.route(to: .filter(type: type, viewModel: viewModel) {
            // Without this, focus returns to whatever sits where the menu was.
            focusedTarget = target
        })
    }

    /// Clears a filter and hands focus to the chip that takes its place.
    private func clear(_ type: ItemFilterType) {
        let remaining = activeTypes.filter { $0 != type }
        let index = min(activeTypes.firstIndex(of: type) ?? 0, remaining.count - 1)

        focusedTarget = remaining.indices.contains(index) ? .chip(remaining[index]) : .menu
        viewModel.reset(filterType: type)
    }

    private func menuEntry(_ type: ItemFilterType, subtitle: String?) -> some View {
        Button {
            route(to: type, from: .menu)
        } label: {
            Text(type.displayTitle)

            if let subtitle {
                Text(subtitle)
            }

            Image(systemName: type.systemImage)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if types.contains(.sortBy) {
            Section {
                menuEntry(.sortBy, subtitle: sortSummary)
            }
        }

        Section {
            ForEach(filterTypes) { type in
                // Menu rows are narrow, so name one value to keep the subtitle on a single line.
                menuEntry(type, subtitle: viewModel.isFilterSelected(type: type) ? summary(for: type, showing: 1) : nil)
            }
        }

        if viewModel.hasActiveFilters {
            Section {
                Button(L10n.reset, systemImage: "xmark", role: .destructive) {
                    focusedTarget = .menu
                    viewModel.reset(filterType: nil)
                }
            }
        }
    }

    private func label(systemImage: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)

            Text(title)
        }
        .lineLimit(1)
        .frame(minHeight: 48)
    }

    private func chip(for type: ItemFilterType) -> some View {
        Button {
            clear(type)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .foregroundStyle(accentColor)

                Text(summary(for: type))

                Image(systemName: "xmark")
                    .fontWeight(.bold)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(minHeight: 48)
        }
        .focused($focusedTarget, equals: .chip(type))
        .accessibilityLabel(type.displayTitle)
        .accessibilityValue(summary(for: type))
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                Menu {
                    menuContent
                } label: {
                    label(systemImage: "line.3.horizontal.decrease", title: L10n.filterAndSort)
                }
                .focused($focusedTarget, equals: .menu)
                .accessibilityLabel(L10n.filterAndSort)

                if types.contains(.sortBy) {
                    Button {
                        route(to: .sortBy, from: .sort)
                    } label: {
                        label(systemImage: ItemFilterType.sortBy.systemImage, title: sortSummary)
                    }
                    .focused($focusedTarget, equals: .sort)
                    .accessibilityLabel(ItemFilterType.sortBy.displayTitle)
                    .accessibilityValue(sortSummary)
                }

                ForEach(activeTypes) { type in
                    chip(for: type)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .font(.callout)
            .controlSize(.large)
            .buttonStyle(.capsule(focusTint: .white))
            .animation(.snappy(duration: 0.2), value: activeTypes)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .focusSection()
    }
}
