//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

private struct ItemActionButtonLabelStyle: LabelStyle {

    @AdaptiveLayout
    private var viewLayout

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isSelected)
    private var isSelected

    var activeColor: Color?

    private var iconSize: CGFloat {
        viewLayout.value(standard: 24, large: 40)
    }

    private var activeSelectionColor: Color? {
        isSelected ? activeColor : nil
    }

    // Focus brightens the button like the Play button's focused glass, keeping an active state's color on the glyph
    private var tint: Color {
        if isFocused {
            return .white
        }

        return activeSelectionColor ?? .gray.opacity(0.15)
    }

    private var foregroundColor: Color {
        if isFocused {
            return activeSelectionColor ?? .black
        }

        return activeSelectionColor?.overlayColor ?? .primary
    }

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .font(.system(size: viewLayout.value(standard: 20, large: 30)))
            .frame(width: iconSize, height: iconSize)
            .padding(viewLayout.value(standard: 8, large: 16))
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: tint,
                    foregroundColor: foregroundColor
                ),
                in: .capsule
            )
    }
}

struct ItemActionButtons: View {

    @AdaptiveLayout
    private var viewLayout

    static let maximumButtons = 4

    @ObservedObject
    var provider: ItemContentGroupProvider

    let buttons: [ItemActionButton]
    let overflowButtons: [ItemActionButton]
    let menuButtons: [ItemActionButton]
    let focusedButton: FocusState<String?>.Binding

    private static func hasTrailers(
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> Bool {
        if enabledTrailers.contains(.local), provider.localTrailers.isNotEmpty {
            return true
        }

        if enabledTrailers.contains(.external), provider.item.remoteTrailers?.isNotEmpty == true {
            return true
        }

        return false
    }

    private static func isAvailable(
        _ button: ItemActionButton,
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> Bool {
        switch button {
        case .played:
            provider.item.canBePlayed
        case .favorited:
            provider.item.canBeFavorited
        case .trailers:
            hasTrailers(for: provider, enabledTrailers: enabledTrailers)
        case .playback:
            provider.item.presentPlayButton && provider.playbackIntent?.mediaSource != nil
        case .shuffle:
            provider.item.canShuffle && !provider.isUnavailable
        case .record:
            provider.item.canBeRecorded
        case .refresh:
            provider.item.canEditMetadata
        case .subtitles:
            provider.item.canEditSubtitles
        case .delete:
            provider.item.canDelete == true
        #if os(iOS)
        case .editMetadata:
            provider.item.canEditMetadata
        #endif
        }
    }

    private static func availableButtons(
        _ buttons: [ItemActionButton],
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> [ItemActionButton] {
        buttons.filter {
            isAvailable($0, for: provider, enabledTrailers: enabledTrailers)
        }
    }

    static func resolvedButtons(
        bar: [ItemActionButton],
        menu: [ItemActionButton],
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
        let bar = availableButtons(bar, for: provider, enabledTrailers: enabledTrailers)
        let menu = availableButtons(menu, for: provider, enabledTrailers: enabledTrailers)

        let hasBarMenu = ViewLayout.platformDefault.isLarge && (menu.isNotEmpty || bar.count > maximumButtons)
        let visible = Array(bar.prefix(hasBarMenu ? maximumButtons - 1 : maximumButtons))
        let overflow = Array(bar.dropFirst(visible.count))

        return (
            visible: visible,
            overflow: overflow,
            menu: menu.subtracting(overflow)
        )
    }

    static func view(for button: ItemActionButton) -> some View {
        Group {
            switch button {
            case .played:
                Played()
            case .favorited:
                Favorited()
            case .trailers:
                Trailers()
            case .playback:
                Playback()
            case .shuffle:
                Shuffle()
            case .record:
                Record()
            case .refresh:
                Refresh()
            case .subtitles:
                Subtitles()
            case .delete:
                Delete()
            #if os(iOS)
            case .editMetadata:
                Edit()
            #endif
            }
        }
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.primary, .secondary)
    }

    private var hasBarMenu: Bool {
        viewLayout.isLarge && (overflowButtons.isNotEmpty || menuButtons.isNotEmpty)
    }

    #if os(tvOS)
    /// The space below the row that a focused button's caption covers without moving the layout
    static var focusedCaptionHeight: CGFloat {
        FocusedCaption.height
    }

    /// What the focused button does, which its icon alone doesn't say
    private func caption(for button: ItemActionButton) -> String {
        switch button {
        case .played:
            provider.item.userData?.isPlayed == true ? L10n.markAsUnplayed : L10n.markAsPlayed
        case .favorited:
            provider.item.userData?.isFavorite == true ? L10n.removeFromFavorites : L10n.addToFavorites
        default:
            button.displayTitle
        }
    }

    /// Captions at either end align with the row's edges so they stay inside the header's column
    private func captionAlignment(for id: String) -> HorizontalAlignment {
        let ids = buttons.map(\.id) + (hasBarMenu ? [ItemView.Component.menu] : [])

        if id == ids.first {
            return .leading
        }

        return id == ids.last ? .trailing : .center
    }
    #endif

    var body: some View {
        if buttons.isNotEmpty || hasBarMenu {
            HStack(alignment: .center, spacing: viewLayout.value(standard: 8, large: 24)) {
                ForEach(buttons) { button in
                    Self.view(for: button)
                        .labelStyle(ItemActionButtonLabelStyle(activeColor: button.activeColor))
                        .focused(focusedButton, equals: button.id)
                        #if os(tvOS)
                        .modifier(FocusedCaption(
                            title: caption(for: button),
                            isFocused: focusedButton.wrappedValue == button.id,
                            alignment: captionAlignment(for: button.id)
                        ))
                        #endif
                }

                if hasBarMenu {
                    Menu {
                        MenuContent(
                            provider: provider,
                            buttons: overflowButtons,
                            menuButtons: menuButtons
                        )
                    } label: {
                        Label(L10n.more, systemImage: "ellipsis")
                    }
                    .menuStyle(.button)
                    .labelStyle(ItemActionButtonLabelStyle())
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary, .secondary)
                    .focused(focusedButton, equals: ItemView.Component.menu)
                    #if os(tvOS)
                    .modifier(FocusedCaption(
                        title: L10n.more,
                        isFocused: focusedButton.wrappedValue == ItemView.Component.menu,
                        alignment: captionAlignment(for: ItemView.Component.menu)
                    ))
                    #endif
                }
            }
            .frame(height: viewLayout.controlHeight)
            // Entering the bar from Play lands on its lead button, not whichever sits under Play's center
            .focusSection()
            .defaultFocus(focusedButton, buttons.first?.id ?? ItemView.Component.menu, priority: .userInitiated)
            .environmentObject(provider)
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .font(.title3)
            .fontWeight(.semibold)
        }
    }
}

extension ItemActionButtons {

    struct Configuration: DynamicProperty {

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        @Default(.Customization.itemBarActionButtons)
        private var barActionButtons
        @Default(.Customization.itemMenuActionButtons)
        private var menuActionButtons

        func resolvedButtons(
            for provider: ItemContentGroupProvider
        ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
            ItemActionButtons.resolvedButtons(
                bar: barActionButtons,
                menu: menuActionButtons,
                for: provider,
                enabledTrailers: enabledTrailers
            )
        }
    }

    struct MenuContent: View {

        @ObservedObject
        var provider: ItemContentGroupProvider

        let buttons: [ItemActionButton]
        let menuButtons: [ItemActionButton]

        var body: some View {
            Group {
                ForEach(
                    buttons,
                    content: ItemActionButtons.view(for:)
                )

                if buttons.isNotEmpty, menuButtons.isNotEmpty {
                    Divider()
                }

                ForEach(
                    menuButtons,
                    content: ItemActionButtons.view(for:)
                )
            }
            .environmentObject(provider)
            .withViewContext(.isInMenu)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
        }
    }
}

#if os(tvOS)
/// Names a focused icon-only button beneath it, like the Apple TV app
private struct FocusedCaption: ViewModifier {

    private static let spacing: CGFloat = 14

    static var height: CGFloat {
        UIFont.preferredFont(forTextStyle: .caption1).lineHeight + spacing
    }

    let title: String
    let isFocused: Bool
    let alignment: HorizontalAlignment

    func body(content: Content) -> some View {
        content
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .bottom)) {
                ZStack {
                    if isFocused {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .alignmentGuide(.bottom) { $0[.top] - Self.spacing }
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .accessibilityHidden(true)
            }
    }
}
#endif
