//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BlurHashKit
import Nuke
import SwiftUI

struct PosterImage<Element: Poster>: View {

    @Environment(\.self)
    private var environment

    private let contentMode: ContentMode
    @SharedPoster
    private var element: Element
    private var pipeline: ImagePipeline
    private let size: PosterDisplayType.Size
    private let displayType: PosterDisplayType

    init(
        item: Element,
        type: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        contentMode: ContentMode = .fill
    ) {
        self.contentMode = contentMode
        self.displayType = type
        self.element = item
        self.pipeline = .shared
        self.size = size
    }

    private var imageSources: [ImageSource] {
        element.imageSources(
            for: displayType,
            size: size,
            environment: element.resolveEnvironment(environment)
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(imageSources)
                    .pipeline(pipeline)
                    .image { image in
                        element.transform(image: image, displayType: displayType)
                    }
                    .placeholder { imageSource in
                        if let blurHash = imageSource.blurHash {
                            Image(
                                blurHash: blurHash,
                                size: .init(width: 8, height: 8)
                            )?
                                .resizable()
                        } else {
                            SystemImageContentView(
                                systemName: element.systemImage
                            )
                        }
                    }
                    .failure {
                        MissingArtworkView(
                            title: element.artworkTitle,
                            systemName: element.systemImage
                        )
                    }
                    .accessibilityRemoveTraits(.isImage)
                    .accessibilityIgnoresInvertColors()
            }
        }
        .posterStyle(
            displayType,
            contentMode: contentMode
        )
    }
}

extension PosterImage {

    func pipeline(_ pipeline: ImagePipeline) -> Self {
        copy(modifying: \.pipeline, with: pipeline)
    }
}

/// Stands in for artwork an item doesn't have: a dark card with a typeset title, so the item stays identifiable
/// without its label and doesn't read as still loading. Thumbnails too small to read a title show the item's symbol.
private struct MissingArtworkView: View {

    private static let minimumTitledLength: CGFloat = 100

    let title: String
    let systemName: String

    var body: some View {
        AlternateLayoutView {
            Color.clear
        } content: { size in
            let length = min(size.width, size.height)

            if length < Self.minimumTitledLength {
                SystemImageContentView(systemName: systemName)
            } else {
                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .padding(length * 0.12)
                    .accessibilityHidden(true)
            }
        }
        .background {
            LinearGradient(
                colors: [Color(white: 0.24), Color(white: 0.11)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .environment(\.colorScheme, .dark)
    }
}
