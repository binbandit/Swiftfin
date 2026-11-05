//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Get
import JellyfinAPI
import SwiftUI

/// Carries pagination counts and a request token until a page is accepted
@MainActor
final class LibraryPageState {

    let pageOffset: Int
    let pageSize: Int
    let userSession: UserSession
    let itemRequest: ItemStore.RequestToken

    init(
        pageOffset: Int,
        pageSize: Int,
        userSession: UserSession
    ) throws {
        self.pageOffset = pageOffset
        self.pageSize = pageSize
        self.userSession = userSession
        self.itemRequest = try userSession.items.beginRequest()
    }

    private var serverItemCount: Int?
    private var totalRows: Int?

    /// Whether the page left out titles whose files are unavailable
    private(set) var hidesUnavailableItems = false

    func items(from response: Response<BaseItemDtoQueryResult>) throws -> [ItemPatch] {
        serverItemCount = response.value.items?.count ?? 0
        totalRows = response.value.totalRecordCount
        return try visibleItems(response.patches())
    }

    func items(from response: Response<[BaseItemDto]>) throws -> [ItemPatch] {
        serverItemCount = response.value.count
        totalRows = response.value.count
        return try visibleItems(response.patches())
    }

    // Every library builds its pages here, so titles without media are hidden from all of them
    private func visibleItems(_ patches: some Collection<ItemPatch>) -> [ItemPatch] {
        let items = userSession.titleAvailability.removingHidden(patches)

        // Some libraries build one page from several responses
        hidesUnavailableItems = hidesUnavailableItems || items.count < patches.count

        return items
    }

    // Server offsets count rows that may be filtered out before they reach the collection
    func progress(returnedCount: Int) -> (nextOffset: Int, hasNextPage: Bool) {
        let serverItemCount = serverItemCount ?? returnedCount
        let nextOffset = pageOffset + serverItemCount
        guard serverItemCount > 0 else { return (nextOffset, false) }

        if let totalRows, totalRows >= nextOffset {
            return (nextOffset, nextOffset < totalRows)
        }
        return (nextOffset, serverItemCount >= pageSize)
    }
}

@MainActor
protocol PagingLibrary<Element> {

    associatedtype Element: Identifiable
    associatedtype PageElement = Element
    associatedtype Environment: WithDefaultValue = Empty
    associatedtype Parent: LibraryParent = TitledLibraryParent

    var environment: Environment? { get }
    var hasNextPage: Bool { get }
    var parent: Parent { get }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [PageElement]

    func materialize(_ page: [PageElement], pageState: LibraryPageState) throws -> [Element]

    func includes(_ element: Element, environment: Environment) -> Bool

    /// Reloads when user data can change this library's membership or ordering
    func shouldRefreshForUserDataChange(environment: Environment) -> Bool

    @ViewBuilder
    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions

    func makeMenuContent(environment: Binding<Environment>) -> AnyView

    #if os(tvOS)
    /// Controls shown under a presented library's title, such as filters
    func makeHeaderAccessory() -> AnyView
    #endif
}

extension PagingLibrary where Element: LibraryElement {

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        Element.supportedLibraryStyleOptions
    }

    func resolvedLibraryStyleOptions(
        environment: Environment,
        elements: some Sequence<Element>
    ) -> LibraryStyleOptions {
        LibraryStyleOptions.resolving(
            elements.map(\.supportedLibraryStyleOptions),
            fallback: libraryStyleOptions(environment: environment)
        )
    }
}

extension PagingLibrary {

    func includes(_ element: Element, environment: Environment) -> Bool {
        true
    }

    func shouldRefreshForUserDataChange(environment: Environment) -> Bool {
        false
    }

    var environment: Environment? {
        nil
    }

    var hasNextPage: Bool {
        true
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        content()
            .eraseToAnyView()
    }

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        .default
    }

    func makeMenuContent(environment: Binding<Environment>) -> AnyView {
        EmptyView()
            .eraseToAnyView()
    }

    #if os(tvOS)
    func makeHeaderAccessory() -> AnyView {
        EmptyView()
            .eraseToAnyView()
    }
    #endif
}

@MainActor
protocol WithRandomElementLibrary<Element, Environment, PageElement>: PagingLibrary {

    func retrieveRandomElement(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> PageElement?
}

@MainActor
protocol SearchablePagingLibrary<Element, Environment, PageElement>: PagingLibrary {

    func retrieveSearchPage(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [PageElement]
}

extension PagingLibrary where PageElement == Element {

    func materialize(_ page: [Element], pageState: LibraryPageState) throws -> [Element] {
        page
    }
}
