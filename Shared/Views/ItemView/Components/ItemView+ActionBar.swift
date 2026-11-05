//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionBar: View {

        @AdaptiveLayout
        private var viewLayout

        @FocusState
        private var focusedButton: String?

        @ObservedObject
        var provider: ItemContentGroupProvider

        private var buttonConfiguration = ItemActionButtons.Configuration()

        let alignment: HorizontalAlignment

        init(
            provider: ItemContentGroupProvider,
            alignment: HorizontalAlignment = .center
        ) {
            self.provider = provider
            self.alignment = alignment
        }

        var body: some View {
            let (visible, overflow, menu) = buttonConfiguration.resolvedButtons(for: provider)
            // Play is disabled without something to play
            let defaultFocusedButton = provider.item.presentPlayButton && provider.playbackIntent != nil ?
                ItemView.Component.play : visible.first?.id ?? ItemView.Component.menu

            VStack(alignment: alignment, spacing: viewLayout.value(standard: 8, large: 24)) {
                if provider.item.presentPlayButton {
                    VStack(spacing: viewLayout.value(standard: 6, large: 12)) {
                        if provider.isUnavailable {
                            UnavailableNotice()
                        } else {
                            PlayButton(provider: provider)
                                .focused($focusedButton, equals: ItemView.Component.play)
                                .frame(height: viewLayout.controlHeight)

                            PlayButton.Details(provider: provider)
                        }
                    }
                }

                ItemActionButtons(
                    provider: provider,
                    buttons: visible,
                    overflowButtons: overflow,
                    menuButtons: menu,
                    focusedButton: $focusedButton
                )
            }
            .focusSection()
            .defaultFocus(
                $focusedButton,
                defaultFocusedButton,
                priority: .userInitiated
            )
            // The page focuses the bar, which picks Play, or its first action when nothing plays
            .coordinatedFocus(ItemView.Component.actions)
            .multilineTextAlignment(.center)
        }
    }
}

/// Takes Play's place when the server can't find an item's files, saying why it can't play
private struct UnavailableNotice: View {

    @AdaptiveLayout
    private var viewLayout

    var body: some View {
        VStack(spacing: viewLayout.value(standard: 6, large: 12)) {
            Label(L10n.unavailable, systemImage: "exclamationmark.circle")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: viewLayout.controlHeight)
                .background(.quinary, in: .capsule)

            Text(L10n.unavailableTitleDescription)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
