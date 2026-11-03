//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct FilterTrack: View {

    @AdaptiveLayout
    private var viewLayout

    enum FocusTarget: Hashable {

        case reset
        case filter(ItemFilterType)

        var title: String {
            switch self {
            case .reset:
                L10n.reset
            case let .filter(type):
                type.displayTitle
            }
        }

        var systemImage: String {
            switch self {
            case .reset:
                "line.3.horizontal.decrease"
            case let .filter(type):
                type.systemImage
            }
        }
    }

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var viewModel: FilterViewModel

    @Router
    private var router

    let types: [ItemFilterType]
    let focus: FocusState<FocusTarget?>.Binding

    private var targets: [FocusTarget] {
        (viewModel.hasActiveFilters ? [.reset] : []) + types.map(FocusTarget.filter)
    }

    private func isSelected(_ target: FocusTarget) -> Bool {
        switch target {
        case .reset:
            true
        case let .filter(type):
            viewModel.isFilterSelected(type: type)
        }
    }

    private func buttonLabel(for target: FocusTarget) -> some View {
        HStack(spacing: viewLayout.value(standard: 4, large: 12)) {
            Image(systemName: target.systemImage)

            Text(target.title)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var resetButton: some View {
        Menu(FocusTarget.reset.title, systemImage: FocusTarget.reset.systemImage) {
            Button(L10n.reset, role: .destructive) {
                viewModel.reset(filterType: nil)
            }
        }
        .labelStyle(.iconOnly)
    }

    private func button(for target: FocusTarget) -> some View {
        Group {
            switch target {
            case .reset:
                resetButton
            case let .filter(type):
                Button {
                    router.route(to: .filter(type: type, viewModel: viewModel))
                } label: {
                    buttonLabel(for: target)
                }
            }
        }
        .focused(focus, equals: target)
        .isSelected(isSelected(target))
        .accessibilityLabel(target.title)
    }

    var body: some View {
        ForEach(targets, id: \.self) { target in
            button(for: target)
                .fixedSize()
        }
        .font(viewLayout.value(standard: .footnote, large: .callout))
        .controlSize(viewLayout.value(standard: .small, large: .large))
        .buttonStyle(.capsule(selectionTint: accentColor, focusTint: viewLayout.value(standard: nil, large: .white)))
    }
}
