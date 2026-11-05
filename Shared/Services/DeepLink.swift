//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation

struct DeepLink: Equatable {

    enum Destination: Equatable {
        case item(id: String)
        case play(id: String)

        // TODO: able to launch library by ID without item pre-retrieval?
//        case library(id: String)
    }

    let serverID: String
    let userID: String
    let destination: Destination

    init(serverID: String, userID: String, destination: Destination) {
        self.serverID = serverID
        self.userID = userID
        self.destination = destination
    }

    init?(_ url: URL) {
        guard let match = url.absoluteString.wholeMatch(
            of: /^(?:swiftfin|jellyfin):\/\/(?<serverID>[A-Za-z0-9-]+)\/(?<userID>[A-Za-z0-9-]+)\/(?<destinationType>item|library|play)\/(?<destinationID>[A-Za-z0-9-]+)\/?$/
        ) else { return nil }

        let destinationID = String(match.output.destinationID)

        self.serverID = String(match.output.serverID)
        self.userID = String(match.output.userID)

        self.destination = match.output.destinationType == "play" ? .play(id: destinationID) : .item(id: destinationID)
    }

    /// The link's URL, or nil when the parser wouldn't accept it back, such as for an ID that isn't plain
    var url: URL? {
        let (destinationType, destinationID) = switch destination {
        case let .item(id):
            ("item", id)
        case let .play(id):
            ("play", id)
        }

        let url = URL(string: "swiftfin://\(serverID)/\(userID)/\(destinationType)/\(destinationID)")

        return url.flatMap(DeepLink.init) == self ? url : nil
    }

    @MainActor
    func open(in tabCoordinator: TabCoordinator) async {
        switch destination {
        case let .item(id):
            await tabCoordinator.open(.item(id: id))

        case let .play(id):
            // Playback presents over the item's page, so leaving the player lands there
            await tabCoordinator.open(.item(id: id))

            // The page says when the server can't find the item's files, where a player would only fail
            guard let userSession = Container.shared.currentUserSession(),
                  let item = try? await userSession.getFullItem(id: id).snapshot,
                  !userSession.titleAvailability.isUnavailable(item)
            else { return }

            Container.shared.userSessionManager().playItem(id: id, userSession: userSession)
        }
    }
}

enum DeepLinkError: Error {
    case missingServer(String)
    case missingUser(String)
}
