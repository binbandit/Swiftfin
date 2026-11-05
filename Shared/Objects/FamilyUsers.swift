//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Accounts shown as sign-in tiles on one server even though the server hides them from its public user list.
///
/// They come from the gitignored `XcodeConfig/FamilyUsers.xcconfig` (format in `FamilyUsers.example.xcconfig`)
/// through the tvOS Info.plist. Builds without that file have none.
struct FamilyUsers: Decodable {

    let serverID: String
    let users: [UserDto]
}

extension FamilyUsers {

    // The xcconfig stores the JSON as URL-safe base64
    private static let configured = (Bundle.main.object(forInfoDictionaryKey: "FamilyUsers") as? String)
        .flatMap { Data(base64Encoded: $0.replacing("-", with: "+").replacing("_", with: "/")) }
        .flatMap { try? JSONDecoder().decode(Self.self, from: $0) }

    /// The configured users for the server with `serverID`
    static func users(forServer serverID: String) -> [UserDto] {
        guard let configured, configured.serverID == serverID else { return [] }

        return configured.users
    }
}
