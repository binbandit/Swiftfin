//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Formats remaining playback time, such as "21 min left" or "1 hr 12 min left".
/// Partial minutes round up, so the last minute reads "1 min left" rather than "0 min left".
struct TimeLeftFormatStyle: FormatStyle {

    func format(_ value: Duration) -> String {
        let duration = value.formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .condensedAbbreviated,
                fractionalPart: .hide(rounded: .up)
            )
        )

        return L10n.durationLeft(duration)
    }
}

extension FormatStyle where Self == TimeLeftFormatStyle {

    static var timeLeft: TimeLeftFormatStyle {
        TimeLeftFormatStyle()
    }
}
