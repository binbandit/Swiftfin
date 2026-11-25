//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import Logging
import Network
import Pulse

@MainActor
@Stateful
final class ConnectToServerViewModel: ObservableObject {

    @CasePathable
    enum Action {
        case addConnection(serverState: ServerState)
        case cancel
        case connect(url: String)
        case searchForServers

        var transition: Transition {
            switch self {
            case .addConnection, .searchForServers: .none
            case .cancel: .to(.initial)
            case .connect: .loop(.connecting)
            }
        }
    }

    enum Event {
        case connected(ServerState)
        case duplicateServer(ServerState)
        case error
    }

    enum State {
        case connecting
        case initial
    }

    /// A server found without typing its address, and how this device reaches it
    struct FoundServer: Hashable, Identifiable {

        /// Most direct first
        enum Route: Comparable {
            case localNetwork
            case tailscale
            case internet
        }

        let server: ServerState
        let route: Route

        var id: String {
            server.id
        }
    }

    // One per server, by its most direct route. Servers no longer found are not cleared, but not an issue.
    @Published
    private(set) var foundServers: [FoundServer] = []

    /// Whether a search has finished, so an empty list means nothing was found
    @Published
    private(set) var hasSearched = false

    let logger = Logger.swiftfin()
    var cancellables = Set<AnyCancellable>()

    @Function(\Action.Cases.connect)
    private func connectToServer(_ url: String) async throws {

        let formattedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .objectReplacement)
            .trimmingCharacters(in: ["/"])
            .prepending("http://", if: !url.contains("://"))

        guard let parsedURL = URL(string: formattedURL)
        else {
            throw ErrorMessage(L10n.invalidURL)
        }

        let url = parsedURL.normalizedServerConnectionURL ?? parsedURL

        guard url.host != nil else {
            throw ErrorMessage(L10n.invalidURL)
        }

        let client = JellyfinClient(
            configuration: .swiftfinConfiguration(url: url),
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
        )

        let response = try await client.send(Paths.getPublicSystemInfo)

        guard let name = response.value.serverName,
              let id = response.value.id
        else {
            logger.critical("Missing server data from network call")
            throw ErrorMessage(L10n.unknownError)
        }

        let connectionURL = processConnectionURL(
            initial: url,
            response: response.response.url
        )

        let newServerState = ServerState(
            urls: [connectionURL],
            currentURL: connectionURL,
            name: name,
            id: id,
            userIDs: []
        )

        let isDuplicateServer = StoredValues[.Server.servers]
            .contains { $0.id == newServerState.id }

        guard !isDuplicateServer else {
            // server has same id, but (possible) new connection URL
            events.send(.duplicateServer(newServerState))
            return
        }

        try await save(server: newServerState)
        events.send(.connected(newServerState))
    }

    // In the event of redirects, get the new host URL from response
    private func processConnectionURL(initial url: URL, response: URL?) -> URL {

        let normalizedURL = url.normalizedServerConnectionURL ?? url

        guard let response else { return normalizedURL }

        if url.scheme != response.scheme ||
            url.host != response.host
        {
            let newURL = response.absoluteString.trimmingSuffix(
                Paths.getPublicSystemInfo.url?.absoluteString ?? ""
            )
            return URL(string: newURL)?.normalizedServerConnectionURL ?? normalizedURL
        }

        return normalizedURL
    }

    private func save(server: ServerState) async throws {

        let publicInfo = try await server.getPublicSystemInfo()

        let newServers = StoredValues[.Server.servers]
            .appending(server)

        StoredValues[.Server.servers] = newServers
        StoredValues[.Server.publicInfo(id: server.id)] = publicInfo
    }

    // server has same id, but (possible) new connection URL
    @Function(\Action.Cases.addConnection)
    private func _addConnection(_ server: ServerState) throws {
        guard let existingServer = StoredValues[.Server.servers].first(where: { $0.id == server.id }) else {
            logger.critical("Could not find server to add new url")
            throw ErrorMessage("An internal error has occurred")
        }

        var connections = existingServer.ensureServerConnections()

        let normalizedURL = server.currentURL.normalizedServerConnectionURL ?? server.currentURL

        let connection = connections.first { $0.url == normalizedURL } ?? {
            let connection = ServerConnection(
                id: UUID().uuidString,
                name: normalizedURL.absoluteString,
                url: normalizedURL,
                interface: .any,
                priority: connections.count
            )
            connections.append(connection)
            return connection
        }()

        existingServer.serverConnections = connections

        existingServer.activeServerConnection = connection
        Notifications[.didChangeServerConnection].post(connection)
    }

    @Function(\Action.Cases.searchForServers)
    private func _searchForServers() async {
        async let configuredServers: Void = probeConfiguredAddresses()

        do {
            for try await server in JellyfinClient.discover() {
                found(
                    ServerState(
                        urls: [server.url],
                        currentURL: server.url,
                        name: server.name,
                        id: server.id,
                        userIDs: []
                    ),
                    isOnLocalNetwork: true
                )
            }
        } catch {
            logger.error("Local server discovery failed: \(error.localizedDescription)")
        }

        await configuredServers
        hasSearched = true
    }

    // Broadcast discovery doesn't cross Tailscale, so addresses set in the build are asked directly
    private func probeConfiguredAddresses() async {
        await withTaskGroup(of: ServerState?.self) { group in
            for url in FamilyServer.addresses {
                group.addTask {
                    await Self.publicServer(at: url)
                }
            }

            for await case let server? in group {
                found(server, isOnLocalNetwork: false)
            }
        }
    }

    private nonisolated static func publicServer(at url: URL) async -> ServerState? {
        let client = JellyfinClient(
            configuration: .swiftfinConfiguration(url: url),
            // An address that isn't reachable, such as Tailscale's while it's off, only stalls, so give up quickly
            sessionConfiguration: .default.mutating(\.timeoutIntervalForRequest, with: 5),
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
        )

        guard let info = try? await client.send(Paths.getPublicSystemInfo).value,
              let name = info.serverName,
              let id = info.id
        else { return nil }

        return ServerState(
            urls: [url],
            currentURL: url,
            name: name,
            id: id,
            userIDs: []
        )
    }

    private func found(_ server: ServerState, isOnLocalNetwork: Bool) {
        let route: FoundServer.Route = if server.currentURL.isTailscale {
            .tailscale
        } else if isOnLocalNetwork {
            .localNetwork
        } else {
            .internet
        }

        let foundServer = FoundServer(server: server, route: route)

        if let index = foundServers.firstIndex(where: { $0.id == server.id }) {
            if route < foundServers[index].route {
                foundServers[index] = foundServer
            }
        } else {
            foundServers.append(foundServer)
        }
    }
}

private extension URL {

    /// Whether the host is a Tailscale address: a MagicDNS name or an IPv4 address in 100.64.0.0/10
    var isTailscale: Bool {
        guard let host = host(percentEncoded: false)?.lowercased() else { return false }

        if host.hasSuffix(".ts.net") {
            return true
        }

        guard let address = IPv4Address(host) else { return false }

        return address.rawValue[0] == 100 && address.rawValue[1] & 0xC0 == 64
    }
}
