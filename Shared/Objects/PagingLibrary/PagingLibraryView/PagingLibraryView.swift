//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import JellyfinAPI
import SwiftUI
import SwiftUIIntrospect

struct PagingLibraryView<Library: PagingLibrary>: View where Library.Element: LibraryElement {

    private enum Focus: String {

        case firstElement = "pagingLibrary-firstElement"
    }

    typealias Element = Library.Element

    @AdaptiveLayout
    private var viewLayout

    @Default(.Customization.Library.rememberLayout)
    private var rememberIndividualLibraryStyle
    @Default(.Customization.Library.style)
    private var defaultLibraryStyle

    @Environment(\.frameForParentView)
    private var frameForParentView

    #if os(tvOS)
    @Environment(\.isPresented)
    private var isPresented
    #endif

    @Namespace
    private var namespace

    @Router
    private var router

    @StateObject
    private var focusCoordinator = FocusCoordinator(waitingFor: Focus.firstElement.rawValue)
    @StateObject
    private var gridProxy = CollectionVGridProxy()
    #if os(tvOS)
    @StateObject
    private var scrollPosition = GridScrollPosition()
    #endif
    @StateObject
    private var viewModel: PagingLibraryViewModel<Library>

    @StoredValue
    private var parentLibraryStyle: LibraryStyle

    @TabItemSelected
    private var tabItemSelected

    private let displayTitle: String?

    private var title: String {
        displayTitle ?? viewModel.library.parent.displayTitle
    }

    #if os(tvOS)
    private var isShowingElements: Bool {
        guard case .content = viewModel.state else { return false }

        return !(viewModel.isSearchActive && viewModel.background.is(.searching)) && viewModel.displayedElements.isNotEmpty
    }
    #endif

    private var libraryStyleOptions: LibraryStyleOptions {
        viewModel.libraryStyleOptions
    }

    private var libraryStyle: LibraryStyle {
        libraryStyleOptions.normalized(storedLibraryStyle)
    }

    private var isLibraryStyleSectionVisible: Bool {
        libraryStyleOptions.hasVisibleControls ||
            (
                libraryStyle.displayType == .list &&
                    libraryStyleOptions.displayTypes.contains(.list) &&
                    viewLayout.canAdjustLibraryListColumns
            )
    }

    private var storedLibraryStyle: LibraryStyle {
        rememberIndividualLibraryStyle ? parentLibraryStyle : defaultLibraryStyle
    }

    private var storedLibraryStyleBinding: Binding<LibraryStyle> {
        rememberIndividualLibraryStyle ? $parentLibraryStyle : $defaultLibraryStyle
    }

    init(library: Library, displayTitle: String? = nil) {
        self.displayTitle = displayTitle
        self._parentLibraryStyle = StoredValue(.User.libraryStyle(id: library.parent.pagingLibraryID))
        self._viewModel = StateObject(wrappedValue: PagingLibraryViewModel(library: library))
    }

    private func contentInsets(for frame: GeometryProxy) -> EdgeInsets {
        #if os(tvOS)
        // The collection disables automatic adjustment, so include both the local
        // safe area (including filter bars) and the tab's measured top inset.
        var insets = frame.safeAreaInsets
        // A presented page's title header clears the top safe area itself.
        insets.top = isPresented ? 0 : max(insets.top, frameForParentView[.tabView]?.safeAreaInsets.top ?? 0)
        insets = insets + viewLayout.itemSpacing
        // Sides without a bar keep the same edge padding as other pages.
        insets.leading = max(insets.leading, viewLayout.edgePadding)
        insets.trailing = max(insets.trailing, viewLayout.edgePadding)
        return insets
        #else
        let horizontalSpacing = libraryStyle.displayType == .list ? 0 : viewLayout.itemSpacing
        return EdgeInsets(
            top: frame.safeAreaInsets.top + viewLayout.itemSpacing,
            leading: horizontalSpacing,
            bottom: frame.safeAreaInsets.bottom + viewLayout.itemSpacing,
            trailing: horizontalSpacing
        )
        #endif
    }

    private var elementsView: some View {
        GeometryReader { geometry in
            let insets = contentInsets(for: geometry)

            CollectionVGrid(
                uniqueElements: viewModel.displayedElements,
                layout: Element.layout(
                    for: libraryStyle,
                    options: libraryStyleOptions,
                    insets: insets,
                    viewLayout: viewLayout.resolving(size: geometry.size)
                )
            ) { element in
                element.makeBody(libraryStyle: libraryStyle)
                    #if os(tvOS)
                        .if(element.id == viewModel.displayedElements.first?.id) { view in
                            view
                                .coordinatedFocus(Focus.firstElement.rawValue)
                                .environmentObject(focusCoordinator)
                        }
                    #endif
            }
            .onReachedBottomEdge(offset: .offset(300)) {
                if viewModel.isSearchActive {
                    viewModel.getNextSearchPage()
                } else {
                    viewModel.getNextPage()
                }
            }
            #if os(tvOS)
            .header(isVisible: isPresented) {
                titleHeader(insets: insets, topSafeArea: geometry.safeAreaInsets.top)
            }
            #endif
            .proxy(gridProxy)
            .onRefresh {
                await viewModel.background.refresh()
            }
            .contentInsetAdjustmentBehavior(.never)
            #if os(tvOS)
            .introspect(.scrollView, on: .tvOS(.v26...)) { scrollView in
                scrollPosition.observe(scrollView)
            }
            .ignoresSafeArea()
            #else
            .ignoresSafeArea(edges: .vertical)
            #endif
        }
        .scrollIndicators(.hidden)
        .withViewContext(.isListRowSeparatorVisible)
        .withViewContext(.isThumb)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                gridProxy.scrollToTop(animated: true)
            }
        }
        #if os(tvOS)
        // Like Home, Menu in a scrolled tab grid returns to the top before it opens the sidebar.
        // Presented grids keep Menu for going back.
        .onExitCommand(perform: !isPresented && scrollPosition.isScrolled ? returnToFirstElement : nil)
        #endif
    }

    #if os(tvOS)
    private func returnToFirstElement() {
        gridProxy.scrollToTop(animated: true)
        focusCoordinator.focus(Focus.firstElement.rawValue)
    }

    /// The tvOS navigation bar stays put over scrolling content, so presented pages hide it
    /// and show their title above the grid instead, where it scrolls away with the items.
    private func titleHeader(insets: EdgeInsets, topSafeArea: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: viewLayout.itemSpacing / 2) {
            HStack(spacing: viewLayout.itemSpacing) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let parent = viewModel.library.parent as? BaseItemDto {
                    ShuffleButton(item: parent)
                        .buttonStyle(.glass)
                        .coordinatedFocus(.secondary)
                }
            }

            viewModel.library.makeHeaderAccessory()
        }
        .padding(.top, topSafeArea)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        // Up from anywhere in the first row reaches Shuffle, not just from below it.
        .focusSection()
        .environmentObject(focusCoordinator)
    }
    #endif

    @ViewBuilder
    private var menuContent: some View {
        if isLibraryStyleSectionVisible {
            LibraryStyleSection(
                libraryStyle: storedLibraryStyleBinding,
                options: libraryStyleOptions,
                canAdjustListColumns: viewLayout.canAdjustLibraryListColumns
            )
        }

        viewModel.library.makeMenuContent(environment: $viewModel.environment)

        if let parent = viewModel.library.parent as? BaseItemDto {
            ShuffleButton(item: parent)
        }

        Button(L10n.random, systemImage: "dice.fill") {
            viewModel.getRandomItem()
        }
    }

    private var libraryContent: some View {
        viewModel.library.makeLibraryBody(viewModel: viewModel) {
            ZStack {
                switch viewModel.state {
                case .initial, .refreshing:
                    ProgressView()
                        #if os(tvOS)
                            .coordinatedFocus(.placeholder)
                        #endif

                case .content:
                    if viewModel.isSearchActive, viewModel.background.is(.searching) {
                        ProgressView()
                    } else if viewModel.displayedElements.isEmpty {
                        ContentUnavailableView(
                            viewModel.isSearchActive ? L10n.noResults.localizedCapitalized : L10n.noItems.localizedCapitalized,
                            systemImage: viewModel.isSearchActive ? "magnifyingglass" : "rectangle.on.rectangle.slash"
                        )
                        .focusable()
                        #if os(tvOS)
                        .coordinatedFocus(.fallback)
                        #endif
                    } else {
                        elementsView
                    }

                case .error:
                    viewModel.error.map(ErrorView.init)
                        #if os(tvOS)
                            .coordinatedFocus(.fallback)
                        #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(tvOS)
            .overlay(alignment: .top) {
                // Without a grid to carry it, the title holds the header's place.
                if isPresented, !isShowingElements {
                    GeometryReader { geometry in
                        titleHeader(insets: contentInsets(for: geometry), topSafeArea: geometry.safeAreaInsets.top)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .ignoresSafeArea()
                    }
                }
            }
            #endif
        }
    }

    var body: some View {
        Group {
            #if os(tvOS)
            // Like Home, span the screen and inset the grid by edge padding instead of the TV safe area.
            libraryContent
                .ignoresSafeArea(.container, edges: .horizontal)
            #else
            GeometryReader { geometry in
                let safeArea = frameForParentView[.navigationStack]?.safeAreaInsets ?? geometry.safeAreaInsets
                let horizontalInsets = EdgeInsets(
                    top: 0,
                    leading: safeArea.leading,
                    bottom: 0,
                    trailing: safeArea.trailing
                )

                libraryContent
                    .layoutContainer(size: CGSize(
                        width: max(0, geometry.size.width - horizontalInsets.leading - horizontalInsets.trailing),
                        height: geometry.size.height
                    ))
                    .padding(horizontalInsets)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .animation(.smooth(duration: 0.35), value: horizontalInsets)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
            #endif
        }
        .animation(.linear(duration: 0.2), value: viewModel.background.is(.gettingNextPage))
        .animation(.linear(duration: 0.2), value: viewModel.background.is(.searching))
        .animation(.linear(duration: 0.2), value: viewModel.elements)
        .animation(.linear(duration: 0.2), value: viewModel.searchElements)
        .navigationTitle(title)
        .errorMessage($viewModel.error)
        #if os(iOS)
        .toolbarTitleDisplayMode(router.isRootOfPath ? .inlineLarge : .inline)
        #endif
        .onChange(of: viewModel.environment) {
            viewModel.refreshForEnvironmentChange()
        }
        .onChange(of: libraryStyle) {
            gridProxy.redraw()
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .gotRandomItem(element):
                element.libraryDidSelectElement(router: router, in: namespace)
            }
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        #if os(tvOS)
        .environmentObject(focusCoordinator)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationBarMenuButton(
            isLoading: viewModel.background.is(.gettingNextPage) || viewModel.background.is(.gettingNextSearchPage)
        ) {
            menuContent
        }
        #endif
    }
}

#if os(tvOS)
/// Follows whether the grid has scrolled away from its top.
private final class GridScrollPosition: ObservableObject {

    @Published
    private(set) var isScrolled = false

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?

    func observe(_ scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }

        self.scrollView = scrollView
        observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
            let isScrolled = scrollView.contentOffset.y > 0

            // Offsets also change during layout, which can be inside a view update.
            DispatchQueue.main.async {
                guard let self, self.isScrolled != isScrolled else { return }

                self.isScrolled = isScrolled
            }
        }
    }
}
#endif
