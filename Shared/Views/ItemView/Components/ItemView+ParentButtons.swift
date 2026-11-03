//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    /// Links to an item's parents, outermost first. Episodes link to their series, then their season.
    struct ParentButtons: View {

        private struct Parent: Identifiable {

            let id: String
            let title: String
        }

        @AdaptiveLayout
        private var viewLayout

        @FocusState
        private var focusedParent: String?

        @Router
        private var router

        @SharedBaseItem
        var item: BaseItemDto

        private var parents: [Parent] {
            let candidates: [(id: String?, title: String?)] = if item.type == .episode {
                [(item.seriesID, item.seriesName), (item.seasonID, item.seasonName)]
            } else {
                [(item.parentRootID, item.parentTitle)]
            }

            return candidates.compactMap { id, title in
                guard let id, let title else { return nil }

                return Parent(id: id, title: title)
            }
        }

        var body: some View {
            let parents = parents

            if parents.isNotEmpty {
                HStack(spacing: viewLayout.value(standard: 8, large: 20)) {
                    ForEach(parents) { parent in
                        Button {
                            router.route(to: .item(id: parent.id))
                        } label: {
                            Label {
                                Text(parent.title)
                            } icon: {
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .focused($focusedParent, equals: parent.id)
                    }
                }
                .lineLimit(1)
                .foregroundStyle(.primary, .secondary)
                .labelStyle(.trailingIcon)
                .buttonStyle(.capsule)
                .controlSize(viewLayout.value(standard: .regular, large: .large))
                .fixedSize(horizontal: false, vertical: true)
                .focusSection()
                .defaultFocus($focusedParent, parents.first?.id, priority: .userInitiated)
            }
        }
    }
}
