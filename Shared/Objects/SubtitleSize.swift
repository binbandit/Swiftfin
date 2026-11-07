//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// How large to draw subtitles, as a percentage of their normal size.
///
/// Applies on top of the caption text style. Image subtitles, such as PGS and VobSub,
/// are pictures at a fixed size, so it doesn't change them.
enum SubtitleSize: Int, CaseIterable, Displayable, Storable {

    case percent75 = 75
    case percent100 = 100
    case percent125 = 125
    case percent150 = 150
    case percent175 = 175
    case percent200 = 200

    var scale: Double {
        Double(rawValue) / 100
    }

    var displayTitle: String {
        scale.formatted(.percent)
    }
}
