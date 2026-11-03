//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct FilterView: View {

    @ObservedObject
    var viewModel: FilterViewModel

    @Router
    private var router

    let type: ItemFilterType

    /// Words sort orders in the current field's terms, such as "A to Z" for names
    private func displayed(_ filters: [AnyItemFilter], in group: ItemFilterType.Group) -> [AnyItemFilter] {
        guard group.keyPath == \ItemFilterCollection.sortOrder.asAnyItemFilter,
              let sortBy = viewModel.currentFilters.sortBy.first
        else { return filters }

        return filters.map { filter in
            let title = ItemSortOrder(rawValue: filter.value).flatMap(sortBy.orderTitle)

            return AnyItemFilter(displayTitle: title ?? filter.displayTitle, value: filter.value)
        }
    }

    @ViewBuilder
    private func selector(group: ItemFilterType.Group) -> some View {
        let source = displayed(viewModel.allFilters[keyPath: group.keyPath], in: group)

        let selectionBinding: Binding<[AnyItemFilter]> = Binding {
            displayed(viewModel.currentFilters[keyPath: group.keyPath], in: group)
        } set: {
            group.setter($0, viewModel)
        }

        if source.isEmpty {
            Text(L10n.none)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            SelectorView(
                selection: selectionBinding,
                sources: source,
                type: group.selectorType
            )
        }
    }

    var body: some View {
        Form(systemImage: type.systemImage) {
            ForEach(type.group) { element in
                Section {
                    selector(group: element)
                } header: {
                    if type.group.count > 1 {
                        Text(element.displayTitle)
                    }
                }
            }
        }
        .navigationTitle(type.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
        .topBarTrailing {
            Button(L10n.reset) {
                viewModel.reset(filterType: type)
            }
            .enabled(viewModel.isFilterSelected(type: type))
        }
    }
}
