//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ConnectToServerView {

    struct FoundServerButton: View {

        @AdaptiveLayout
        private var viewLayout

        let foundServer: ConnectToServerViewModel.FoundServer
        let action: () -> Void

        // How the server is reached says more than its address
        private var routeDescription: String {
            switch foundServer.route {
            case .localNetwork:
                L10n.onThisNetwork
            case .tailscale:
                L10n.viaTailscale
            case .internet:
                foundServer.server.currentURL.absoluteString
            }
        }

        var body: some View {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(foundServer.server.name)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(routeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.body)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
                .padding(viewLayout.value(standard: 0, large: 16))
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.card)
        }
    }
}
