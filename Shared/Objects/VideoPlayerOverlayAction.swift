//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

@MainActor
protocol VideoPlayerOverlayActionProviding {

    var id: String { get }
    var overlayActions: [VideoPlayerOverlayAction] { get }
}

@MainActor
struct VideoPlayerOverlayAction: Identifiable {

    let id: String
    let title: String
    let systemImage: String?
    /// The item the action plays, previewed beside it.
    let preview: BaseItemDto?
    let action: @MainActor () -> Void

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        preview: BaseItemDto? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.preview = preview
        self.action = action
    }
}
