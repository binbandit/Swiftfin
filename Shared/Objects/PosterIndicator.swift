//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@OptionSet<Int>
struct PosterIndicator: Hashable, Storable {

    private enum Options: Int {
        case favorited
        case played
        case progress
        case unplayed
        case newEpisodes
    }

    static var all: Self {
        [.favorited, .played, .progress, .unplayed, .newEpisodes]
    }
}

// MARK: - Codable

/// A saved list also records the indicators that existed when it was saved, so ones added later start on,
/// like any new setting, rather than looking turned off by someone who never saw them.
///
/// Both share one integer: the turned on indicators in the lower half, which is all that older versions read,
/// and the known ones in the upper half.
extension PosterIndicator {

    /// The indicators that existed before lists recorded them
    private static let unrecorded: Self = [.favorited, .played, .progress, .unplayed]

    private static let knownShift = 32

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(RawValue.self)
        let enabled = Self(rawValue: value & ((1 << Self.knownShift) - 1))
        let known = Self(rawValue: value >> Self.knownShift)

        // Turning every indicator off asks for clean posters, so new ones stay off too.
        guard !enabled.isEmpty else {
            self = enabled
            return
        }

        self = enabled.union(Self.all.subtracting(known.isEmpty ? Self.unrecorded : known))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue | (Self.all.rawValue << Self.knownShift))
    }
}
