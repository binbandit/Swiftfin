//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// The family's own server: accounts it hides from its public user list, and addresses it can be reached at.
///
/// It comes from the gitignored `XcodeConfig/FamilyServer.xcconfig` (format in `FamilyServer.example.xcconfig`)
/// through the tvOS Info.plist. Builds without that file have none.
struct FamilyServer: Decodable {

    let serverID: String

    /// Accounts shown as sign-in tiles on this server only
    let users: [UserDto]

    /// Addresses the add-server screen tries on its own, such as the server's Tailscale address
    let addresses: [URL]

    private enum CodingKeys: String, CodingKey {
        case serverID
        case users
        case addresses
    }

    // Either list may be left out
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.serverID = try container.decode(String.self, forKey: .serverID)
        self.users = try container.decodeIfPresent([UserDto].self, forKey: .users) ?? []
        self.addresses = try container.decodeIfPresent([URL].self, forKey: .addresses) ?? []
    }
}

extension FamilyServer {

    // The xcconfig stores the JSON as URL-safe base64
    private static let configured = (Bundle.main.object(forInfoDictionaryKey: "FamilyServer") as? String)
        .flatMap { Data(base64Encoded: $0.replacing("-", with: "+").replacing("_", with: "/")) }
        .flatMap { try? JSONDecoder().decode(Self.self, from: $0) }

    /// The configured users for the server with `serverID`
    static func users(forServer serverID: String) -> [UserDto] {
        guard let configured, configured.serverID == serverID else { return [] }

        return configured.users
    }

    static var addresses: [URL] {
        configured?.addresses ?? []
    }
}
