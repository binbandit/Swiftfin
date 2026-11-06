//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension VideoPlayer {

    struct OverlayActions: View {

        @AdaptiveLayout
        private var viewLayout

        @Environment(ViewState.self)
        private var viewState

        @FocusState
        private var focusedAction: String?

        private var actions: [ViewState.OverlayAction] {
            viewState.visibleElements.contains(.overlayActions) ? viewState.overlayActions : []
        }

        #if os(tvOS)
        /// The item a previewing action plays, shown while nothing covers the video.
        private var preview: BaseItemDto? {
            guard viewState.presentation == .hidden else { return nil }

            return actions.lazy.compactMap(\.button.preview).first
        }
        #endif

        var body: some View {
            ViewThatFits(in: .horizontal) {
                buttons(axis: .horizontal)
                #if os(tvOS)
                ScrollView(.horizontal) {
                    buttons(axis: .horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .fixedSize(horizontal: false, vertical: true)
                #else
                buttons(axis: .vertical)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            #if os(tvOS)
            // Grows up from a zero-height frame on the actions' top edge, so the actions
            // hold their place as the preview comes and goes.
            .overlay(alignment: .topTrailing) {
                ZStack {
                    if let preview {
                        UpNextPreview(item: preview)
                            .fixedSize()
                            .padding(.bottom, 32)
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    }
                }
                .frame(height: 0, alignment: .bottom)
            }
            .animation(.easeOut(duration: 0.3), value: preview?.id)
            .focusSection()
            .onMoveCommand { direction in
                if viewState.presentation == .hidden, direction == .up || direction == .down {
                    viewState.showControls()
                }
            }
            .onChange(of: actions.map(\.id), initial: true) { oldIDs, _ in
                viewState.updateOverlayActionFocus(previousIDs: oldIDs)
            }
            .onChange(of: viewState.presentation) {
                viewState.updateOverlayActionFocus()
            }
            .onChange(of: viewState.isPresentingCloseConfirmation) {
                if !viewState.isPresentingCloseConfirmation {
                    viewState.updateOverlayActionFocus()
                }
            }
            #endif
        }

        private func buttons(axis: Axis) -> some View {
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: viewLayout.isLarge ? 24 : 12))
                : AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))

            return layout {
                ForEach(actions) { action in
                    Button {
                        viewState.performOverlayAction(action.id)
                    } label: {
                        #if os(tvOS)
                        Text(action.button.title)
                        #else
                        if let systemImage = action.button.systemImage {
                            Label(action.button.title, systemImage: systemImage)
                        } else {
                            Text(action.button.title)
                        }
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(ContextualActionButtonStyle())
                    #else
                        .buttonStyle(OverlayActionButtonStyle())
                    #endif
                    .coordinatedFocus(action.id.focusID, selection: $focusedAction)
                }
            }
        }
    }

    #if os(tvOS)
    /// Matches the system player's contextual actions, such as its Skip Intro: text only, glass at rest, light and lifted when focused.
    /// Its height matches the supplement tabs that share its row.
    private struct ContextualActionButtonStyle: ButtonStyle {

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.accessibilityReduceMotion)
        private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(isFocused ? .black : .white)
                .lineLimit(1)
                .padding(.horizontal, 40)
                .padding(.vertical, 11)
                .background {
                    // The fill replaces the glass instead of tinting it, which would shade its edges,
                    // and carries the shadow so the label doesn't cast one onto it.
                    ZStack {
                        Color.clear
                            .backport
                            .glassEffect(.regular.visible(!isFocused), in: .capsule)

                        Capsule()
                            .fill(Color(white: 0.92))
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                            .opacity(isFocused ? 1 : 0)
                    }
                }
                .contentShape(.capsule)
                .scaleEffect(isFocused && !reduceMotion ? 1.14 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    /// The episode a Next Episode action plays: its still, number and title on a glass card.
    private struct UpNextPreview: View {

        let item: BaseItemDto

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                PosterImage(item: item, type: .landscape, size: .custom(width: 360))
                    .posterAspectRatio(.landscape)
                    .frame(width: 360)
                    // Concentric with the card: its corner radius less its padding.
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    if let label = item.seasonEpisodeLabel {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.displayTitle)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 360, alignment: .leading)
            .padding(14)
            .backport
            .glassEffect(.regular.interactive(false), in: .rect(cornerRadius: 26))
            .accessibilityElement(children: .combine)
        }
    }
    #endif

    #if os(iOS)
    private struct OverlayActionButtonStyle: ButtonStyle {

        @AdaptiveLayout
        private var viewLayout

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.isEnabled)
        private var isEnabled
        @Environment(\.accessibilityReduceMotion)
        private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.black)
                .symbolRenderingMode(.monochrome)
                .padding(.horizontal, viewLayout.isLarge ? 28 : 20)
                .padding(.vertical, viewLayout.isLarge ? 16 : 10)
                .frame(minHeight: 44)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0.2), radius: isFocused ? 12 : 4)
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.5)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    #endif
}
