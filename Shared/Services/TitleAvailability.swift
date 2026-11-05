//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import Get
import JellyfinAPI
import Logging

/// Finds titles whose media files the server can no longer open, such as after a drive fails, so their pages can say so
/// and, with the Hide unavailable titles setting, so they can be hidden.
///
/// The server keeps listing these titles with their metadata, so a background check asks it to open files instead.
/// Titles in the same storage folder, like `/media/Movies`, are lost together, so a few probes decide a whole folder.
/// A series merged from several folders can lose some of them, and then borrows artwork from the series in one that's left.
/// Results are cached per server so they apply before rows load, and are checked again daily.
@MainActor
final class TitleAvailability: UserSessionService {

    private nonisolated static let maxAge: TimeInterval = 24 * 60 * 60
    private static let firstCheckTimeout: Duration = .seconds(4)

    private let logger = Logger.swiftfin()
    private let changeSubject = PassthroughSubject<Void, Never>()

    private var results: CheckResults?
    private var check: Task<Void, Never>?
    private var firstCheckWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// Sends when the hidden titles change, after a check finds a difference while hiding or the setting changes
    var changes: AnyPublisher<Void, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    private var isEnabled: Bool {
        Defaults[.Customization.hideUnavailableTitles]
    }

    /// Only a definite missing file makes a title unavailable. Titles that haven't been checked are available.
    func isUnavailable(_ item: BaseItemDto) -> Bool {
        guard let results else { return false }

        switch item.type {
        case .episode:
            // An episode belongs to the season folder holding its file, even when a merged series lists it under another season
            return results.missingSeasonIDs.contains(item.seasonID) || results.unavailableTitleIDs.contains(item.seriesID)
        default:
            return results.unavailableTitleIDs.contains(item.id)
        }
    }

    func isUnavailable(id: String?) -> Bool {
        results?.unavailableTitleIDs.contains(id) == true
    }

    /// Whether rows leave out a title, which only the Hide unavailable titles setting does
    func isHidden(_ item: BaseItemDto) -> Bool {
        isEnabled && isUnavailable(item)
    }

    func isHidden(id: String?) -> Bool {
        isEnabled && isUnavailable(id: id)
    }

    func removingHidden(_ patches: some Sequence<ItemPatch>) -> [ItemPatch] {
        patches.filter { !isHidden($0.value) }
    }

    /// The series holding a merged series' remaining seasons, whose artwork stands in when the series' own was lost with its files
    func artworkStandIn(forSeriesID id: String) -> BaseItemDto? {
        results?.artworkStandIns[id]
    }

    /// Waits a few seconds for a server's first check, so its first rows don't show titles that are about to be hidden
    func prepared() async {
        guard isEnabled, results == nil, check != nil else { return }

        let id = UUID()

        await withCheckedContinuation { continuation in
            firstCheckWaiters[id] = continuation

            Task {
                try? await Task.sleep(for: Self.firstCheckTimeout)
                self.firstCheckWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    func willStart(userSession: UserSession) async {
        results = CheckResults.load(serverID: userSession.server.id)
    }

    func didStart(userSession: UserSession) {
        Defaults.publisher(.Customization.hideUnavailableTitles, options: [])
            .sink { [weak self, weak userSession] _ in
                guard let self, let userSession else { return }

                // Loaded rows reload with or without the hidden titles
                userSession.items.libraryDidChange()
                self.changeSubject.send()
            }
            .store(in: &cancellables)

        // A library scan may follow a drive coming back
        userSession.items
            .changes
            .filter {
                if case .libraryChanged = $0 {
                    true
                } else {
                    false
                }
            }
            .debounce(for: .seconds(30), scheduler: RunLoop.main)
            .sink { [weak self, weak userSession] _ in
                guard let userSession else { return }

                self?.checkIfStale(userSession: userSession, maxAge: 10 * 60)
            }
            .store(in: &cancellables)

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self, weak userSession] in
                guard let userSession else { return }

                self?.checkIfStale(userSession: userSession)
            }
            .store(in: &cancellables)

        checkIfStale(userSession: userSession)
    }

    func willStop(userSession: UserSession) {
        cancellables.removeAll()
        check?.cancel()
        check = nil
        resumeFirstCheckWaiters()
    }

    private func checkIfStale(userSession: UserSession, maxAge: TimeInterval = maxAge) {
        if let checkedAt = results?.checkedAt, Date.now.timeIntervalSince(checkedAt) < maxAge {
            return
        }

        startCheck(userSession: userSession)
    }

    private func startCheck(userSession: UserSession) {
        guard check == nil else { return }

        check = Task {
            await runCheck(userSession: userSession)

            check = nil
            resumeFirstCheckWaiters()
        }
    }

    private func runCheck(userSession: UserSession) async {
        let start = ContinuousClock.now
        let check = AvailabilityCheck(userSession: userSession, previous: results)

        do {
            let results = try await check.run()
            try Task.checkCancellation()

            let didChange = results.unavailableTitleIDs != self.results?.unavailableTitleIDs ||
                results.missingSeasonIDs != self.results?.missingSeasonIDs

            self.results = results
            try? results.store(serverID: userSession.server.id)

            logger.info(
                "Checked title availability",
                metadata: [
                    "requests": .stringConvertible(check.requestCount),
                    "duration": .stringConvertible(ContinuousClock.now - start),
                    "unavailableTitles": .stringConvertible(results.unavailableTitleIDs.count),
                    "missingSeasons": .stringConvertible(results.missingSeasonIDs.count),
                ]
            )

            // Rows on screen keep their titles until they next load
            if didChange, isEnabled {
                changeSubject.send()
            }
        } catch {
            guard !Task.isCancelled else { return }

            // Earlier results stay until a check succeeds
            logger.error(
                "Unable to check title availability",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    private func resumeFirstCheckWaiters() {
        for waiter in firstCheckWaiters.values {
            waiter.resume()
        }

        firstCheckWaiters.removeAll()
    }
}

/// The last check's results for a server
private struct CheckResults: Codable {

    let checkedAt: Date
    /// Movies, series, seasons, and collections with nothing left to play
    let unavailableTitleIDs: Set<String>
    /// Season folders whose episode files are gone
    let missingSeasonIDs: Set<String>
    /// Partly unavailable merged series, by ID, and the series holding their remaining seasons
    let artworkStandIns: [String: BaseItemDto]

    private static func url(serverID: String) -> URL {
        URL.cachesDirectory
            .appending(path: "TitleAvailability", directoryHint: .isDirectory)
            .appending(path: "\(serverID).json", directoryHint: .notDirectory)
    }

    static func load(serverID: String) -> Self? {
        try? JSONDecoder().decode(Self.self, from: Data(contentsOf: url(serverID: serverID)))
    }

    func store(serverID: String) throws {
        let url = Self.url(serverID: serverID)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// One pass over a server's titles
///
/// Movie files and season folders are probed through their storage folder. When a folder's probes disagree, each
/// title in it is probed. Series, seasons, and collections are unavailable when nothing in them can play.
@MainActor
private final class AvailabilityCheck {

    private enum Probe {

        case available
        case unavailable
        case inconclusive
    }

    private enum FolderState {

        case available
        case unavailable
        case mixed
        case inconclusive
    }

    private static let maxConcurrentRequests = 4
    private static let maxSamplesPerFolder = 10
    private static let unavailableSamplesToHideFolder = 5
    private static let maxProbesPerMixedFolder = 200

    private let userSession: UserSession
    private let previous: CheckResults?
    private let previouslyMissingIDs: Set<String>

    private var availableRequestSlots = maxConcurrentRequests
    private var requestQueue: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    /// Partly unavailable merged series, by ID, and the series holding their latest remaining season
    private var standInSeriesIDs: [String: String] = [:]

    init(userSession: UserSession, previous: CheckResults?) {
        self.userSession = userSession
        self.previous = previous
        self.previouslyMissingIDs = previous.map { $0.unavailableTitleIDs.union($0.missingSeasonIDs) } ?? []
    }

    func run() async throws -> CheckResults {
        let catalog = try await catalog()

        // A movie's file or a season's folder sits in its title's folder, which sits in a storage folder
        let folders = Dictionary(
            grouping: catalog.filter { [.movie, .musicVideo, .video, .season].contains($0.type) && $0.path != nil },
            by: { $0.path?.storageFolder ?? "" }
        )

        let missingIDs = await concurrentUnion(folders.values) { await self.missingIDs(in: $0) }
        let missingSeasonIDs = missingIDs.intersection(catalog.filter { $0.type == .season }.compactMap(\.id))

        var unavailableTitleIDs = missingIDs.subtracting(missingSeasonIDs)
        await unavailableTitleIDs.formUnion(unavailableShowIDs(in: catalog, missingSeasonIDs: missingSeasonIDs))
        await unavailableTitleIDs.formUnion(unavailableCollectionIDs(in: catalog, unavailableTitleIDs: unavailableTitleIDs))

        return await CheckResults(
            checkedAt: .now,
            unavailableTitleIDs: unavailableTitleIDs,
            missingSeasonIDs: missingSeasonIDs,
            artworkStandIns: artworkStandIns()
        )
    }

    // MARK: - Catalog

    private func catalog() async throws -> [BaseItemDto] {
        var items: [BaseItemDto] = []

        while true {
            var parameters = Paths.GetItemsParameters()
            parameters.enableImages = false
            parameters.enableUserData = false
            parameters.fields = [.path, .childCount]
            parameters.includeItemTypes = [.movie, .musicVideo, .video, .series, .season, .boxSet]
            parameters.isRecursive = true
            parameters.limit = 1000
            parameters.startIndex = items.count
            parameters.userID = userSession.user.id

            let page = try await limited {
                try await self.userSession.client.send(Paths.getItems(parameters: parameters)).value
            }
            let pageItems = page.items ?? []

            items += pageItems

            guard pageItems.isNotEmpty, items.count < page.totalRecordCount ?? 0 else { return items }
        }
    }

    // MARK: - Media

    private func missingIDs(in folder: [BaseItemDto]) async -> Set<String> {
        let ids = folder.compactMap(\.id)

        switch await state(of: folder) {
        case .available:
            return []
        case .unavailable:
            return Set(ids)
        case .mixed:
            return await missingIDs(probingEach: folder)
        case .inconclusive:
            // Errors never hide or reveal titles
            return previouslyMissingIDs.intersection(ids)
        }
    }

    /// Probes titles spread across a folder until they disagree or agree enough
    private func state(of folder: [BaseItemDto]) async -> FolderState {
        let count = min(folder.count, Self.maxSamplesPerFolder)
        // Alternating halves, so the first few samples already span the folder
        let positions = Array(stride(from: 0, to: count, by: 2)) + Array(stride(from: 1, to: count, by: 2))

        var availableCount = 0
        var unavailableCount = 0

        for position in positions {
            switch await probe(folder[position * folder.count / count]) {
            case .available:
                availableCount += 1
            case .unavailable:
                unavailableCount += 1
            case .inconclusive:
                continue
            }

            if availableCount > 0, unavailableCount > 0 {
                return .mixed
            }

            // Showing titles is the safe outcome, so it takes less evidence than hiding a folder
            if availableCount == 2 {
                return .available
            }

            if unavailableCount == Self.unavailableSamplesToHideFolder {
                return .unavailable
            }
        }

        if availableCount > 0 {
            return .available
        }

        // A small folder can run out of titles to sample
        return unavailableCount > 0 && count == folder.count ? .unavailable : .inconclusive
    }

    private func missingIDs(probingEach folder: [BaseItemDto]) async -> Set<String> {
        let probed = folder.prefix(Self.maxProbesPerMixedFolder)
        let unprobedIDs = folder.dropFirst(probed.count).compactMap(\.id)

        let missingIDs = await concurrentUnion(probed) { item -> Set<String> in
            guard let id = item.id else { return [] }

            switch await self.probe(item) {
            case .available:
                return []
            case .unavailable:
                return [id]
            case .inconclusive:
                return self.previouslyMissingIDs.contains(id) ? [id] : []
            }
        }

        return missingIDs.union(previouslyMissingIDs.intersection(unprobedIDs))
    }

    /// Asks the server for a file's headers, the request that starts direct playback
    private func probe(_ item: BaseItemDto) async -> Probe {
        let fileID = item.type == .season ? await storedEpisodeID(in: item) : item.id

        guard let fileID else { return .inconclusive }

        var parameters = Paths.HeadVideoStreamParameters()
        parameters.isStatic = true

        do {
            _ = try await limited {
                try await self.userSession.client.data(for: Paths.headVideoStream(itemID: fileID, parameters: parameters)) {
                    $0.timeoutInterval = 10
                }
            }
            return .available
        } catch let APIError.unacceptableStatusCode(statusCode) where statusCode == 404 || statusCode == 410 {
            return .unavailable
        } catch {
            return .inconclusive
        }
    }

    /// An episode whose file is in the season's own folder, since a merged series lists other folders' episodes here too
    private func storedEpisodeID(in season: BaseItemDto) async -> String? {
        try? await episodes(in: season, limit: 5).first { $0.seasonID == season.id }?.id
    }

    private func episodes(in season: BaseItemDto, limit: Int? = nil) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableImages = false
        parameters.enableTotalRecordCount = false
        parameters.enableUserData = false
        parameters.includeItemTypes = [.episode]
        parameters.isMissing = false
        parameters.limit = limit
        parameters.parentID = season.id
        parameters.userID = userSession.user.id

        return try await limited {
            try await self.userSession.client.send(Paths.getItems(parameters: parameters)).value.items ?? []
        }
    }

    // MARK: - Shows and Collections

    /// Seasons with no episodes left, and series with no seasons left
    private func unavailableShowIDs(in catalog: [BaseItemDto], missingSeasonIDs: Set<String>) async -> Set<String> {
        let seasons = catalog.filter { $0.type == .season }
        let seasonsBySeries = Dictionary(grouping: seasons, by: \.seriesID)
        // A merged series shares its name with the series whose seasons it lists
        let namesWithMissingSeasons = Set(seasons.filter { missingSeasonIDs.contains($0.id) }.compactMap(\.seriesName))

        return await concurrentUnion(catalog.filter { $0.type == .series }) { series -> Set<String> in
            guard let id = series.id else { return [] }

            let ownSeasons = seasonsBySeries[id] ?? []

            // A series found in several library folders is merged, listing seasons stored under other series
            guard series.childCount != ownSeasons.count else {
                return Self.unavailableIDs(of: id, seasons: ownSeasons) { missingSeasonIDs.contains($0.id) }
            }
            guard let name = series.name, namesWithMissingSeasons.contains(name) else { return [] }

            return await self.unavailableIDs(ofMergedSeries: id, missingSeasonIDs: missingSeasonIDs)
        }
    }

    /// A merged series' season can list episodes stored in other folders, so its episodes decide
    private func unavailableIDs(ofMergedSeries id: String, missingSeasonIDs: Set<String>) async -> Set<String> {
        var parameters = Paths.GetSeasonsParameters()
        parameters.enableImages = false
        parameters.enableUserData = false
        parameters.fields = [.path]
        parameters.userID = userSession.user.id

        guard let seasons = try? await limited({
            try await self.userSession.client.send(Paths.getSeasons(seriesID: id, parameters: parameters)).value.items ?? []
        }) else {
            return previous?.unavailableTitleIDs.contains(id) == true ? [id] : []
        }

        let emptySeasonIDs = await concurrentUnion(seasons.filter { missingSeasonIDs.contains($0.id) }) { season -> Set<String> in
            guard let seasonID = season.id, let episodes = try? await self.episodes(in: season) else { return [] }

            return episodes.isNotEmpty && episodes.allSatisfy { missingSeasonIDs.contains($0.seasonID) } ? [seasonID] : []
        }

        // Seasons stored in another library folder are listed with the ID of the series there, whose artwork can stand in
        if let standInID = seasons.last(where: { $0.path != nil && !missingSeasonIDs.contains($0.id) })?.seriesID, standInID != id {
            standInSeriesIDs[id] = standInID
        }

        return Self.unavailableIDs(of: id, seasons: seasons) { emptySeasonIDs.contains($0.id) }
    }

    /// Collections whose every title is unavailable, checked only when some titles are
    private func unavailableCollectionIDs(in catalog: [BaseItemDto], unavailableTitleIDs: Set<String>) async -> Set<String> {
        guard unavailableTitleIDs.isNotEmpty else { return [] }

        let collections = catalog.filter { $0.type == .boxSet && ($0.childCount ?? 0) > 0 }

        return await concurrentUnion(collections) { collection -> Set<String> in
            guard let id = collection.id else { return [] }

            var parameters = Paths.GetItemsParameters()
            parameters.enableImages = false
            parameters.enableTotalRecordCount = false
            parameters.enableUserData = false
            parameters.parentID = id
            parameters.userID = self.userSession.user.id

            guard let titleIDs = try? await self.limited({
                try await self.userSession.client.send(Paths.getItems(parameters: parameters)).value.items?.compactMap(\.id)
            }) else {
                return self.previous?.unavailableTitleIDs.contains(id) == true ? [id] : []
            }

            return titleIDs.isNotEmpty && titleIDs.allSatisfy(unavailableTitleIDs.contains) ? [id] : []
        }
    }

    /// A series' unavailable seasons, and the series too when none of its seasons are left.
    /// Seasons without a folder are placeholders for missing ones and don't count.
    private static func unavailableIDs(
        of seriesID: String,
        seasons: [BaseItemDto],
        isUnavailable: (BaseItemDto) -> Bool
    ) -> Set<String> {
        let storedSeasons = seasons.filter { $0.path != nil }
        let unavailableIDs = Set(storedSeasons.filter(isUnavailable).compactMap(\.id))

        guard storedSeasons.isNotEmpty, unavailableIDs.count == storedSeasons.count else { return unavailableIDs }

        return unavailableIDs.union([seriesID])
    }

    // MARK: - Artwork

    /// The series standing in for partly unavailable merged series, with their image tags. Errors keep the previous ones.
    private func artworkStandIns() async -> [String: BaseItemDto] {
        guard standInSeriesIDs.isNotEmpty else { return [:] }

        var parameters = Paths.GetItemsParameters()
        parameters.enableTotalRecordCount = false
        parameters.enableUserData = false
        parameters.ids = Array(Set(standInSeriesIDs.values))
        parameters.imageTypeLimit = 1
        parameters.userID = userSession.user.id

        guard let series = try? await limited({
            try await self.userSession.client.send(Paths.getItems(parameters: parameters)).value.items ?? []
        }) else {
            return previous?.artworkStandIns ?? [:]
        }

        let seriesByID = Dictionary(series.compactMap { item in item.id.map { ($0, item) } }) { first, _ in first }

        return standInSeriesIDs.compactMapValues { seriesByID[$0] }
    }

    // MARK: - Requests

    /// Keeps a few requests in flight so a check doesn't crowd out browsing
    private func limited<T>(_ request: () async throws -> T) async throws -> T {
        if availableRequestSlots > 0 {
            availableRequestSlots -= 1
        } else {
            await withCheckedContinuation { requestQueue.append($0) }
        }

        defer {
            if requestQueue.isEmpty {
                availableRequestSlots += 1
            } else {
                requestQueue.removeFirst().resume()
            }
        }

        requestCount += 1

        return try await request()
    }

    private func concurrentUnion<C: Collection>(
        _ elements: C,
        _ transform: @escaping (C.Element) async -> Set<String>
    ) async -> Set<String> {
        await withTaskGroup(of: Set<String>.self) { group in
            for element in elements {
                group.addTask { await transform(element) }
            }

            return await group.reduce(into: []) { $0.formUnion($1) }
        }
    }
}

private extension Set<String> {

    func contains(_ id: String?) -> Bool {
        id.map { contains($0) } ?? false
    }
}

private extension String {

    /// The folder holding a title's own folder, like `/media/Movies` for `/media/Movies/Heat (1995)/Heat.mkv`
    /// or `/media/Shows` for the season folder `/media/Shows/Andor/Season 1`
    var storageFolder: String {
        var folder = self[...]

        for _ in 0 ..< 2 {
            guard let separator = folder.lastIndex(where: { $0 == "/" || $0 == "\\" }) else { return "" }

            folder = folder[..<separator]
        }

        return String(folder)
    }
}
