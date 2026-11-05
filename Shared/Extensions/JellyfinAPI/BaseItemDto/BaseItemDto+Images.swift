//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import UIKit

@MainActor
extension BaseItemDto {

    /// For a series merged from several library folders whose artwork was lost along with some of its files,
    /// the series holding its remaining seasons, whose artwork is shown once the series' own fails to load
    var artworkStandIn: BaseItemDto? {
        guard type == .series, let id else { return nil }

        return Container.shared.currentUserSession()?.titleAvailability.artworkStandIn(forSeriesID: id)
    }

    /// The item's own image of a type, then the same image of its artwork stand-in for when the item's fails to load
    func imageSources(_ type: ImageType, standIn: BaseItemDto?, environment: some WithImageSourceOptions) -> [ImageSource] {
        [
            imageSource(type, itemID: id, environment: environment),
            standIn.flatMap { $0.imageSource(type, itemID: $0.id, environment: environment) },
        ]
            .compactMap(\.self)
    }

    func imageSource(
        _ type: ImageType,
        itemID: String?,
        tag: String? = nil,
        environment: some WithImageSourceOptions
    ) -> ImageSource? {
        let imageTag: String? = switch type {
        case .backdrop:
            backdropImageTags?.first
        case .screenshot:
            screenshotImageTags?.first
        default:
            imageTags?[type.rawValue]
        }

        guard let itemID, itemID.isNotEmpty,
              let tag = tag ?? (itemID == id ? imageTag : nil), tag.isNotEmpty,
              let client = Container.shared.currentUserSession()?.client
        else { return nil }

        // TODO: put into environment?
        let scale = UITraitCollection.current.displayScale

        let parameters = Paths.GetItemImageParameters(
            maxWidth: environment.maxWidth.map { Int($0 * scale) },
            maxHeight: environment.maxHeight.map { Int($0 * scale) },
            quality: environment.quality.map { clamp($0, min: 1, max: 100) },
            tag: tag,
            format: type == .logo ? .png : nil
        )

        let request = Paths.getItemImage(
            itemID: itemID,
            imageType: type.rawValue,
            parameters: parameters
        )

        guard let url = client.url(with: request) else { return nil }

        let blurHashes = itemID == id && type != .logo ? imageBlurHashes?[type] : nil

        return ImageSource(
            url: url,
            blurHash: blurHashes?[tag] ?? blurHashes?.values.first
        )
    }
}
