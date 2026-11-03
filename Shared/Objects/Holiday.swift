//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

/// A holiday that adds a themed row to Home while it's in season.
enum Holiday: String, CaseIterable, Defaults.Serializable, Displayable {

    case halloween
    case christmas

    /// The holiday in season right now, if any.
    static var current: Holiday? {
        #if DEBUG
        if let preview = Defaults[.previewHoliday] {
            return preview
        }
        #endif

        return current(on: .now)
    }

    static func current(on date: Date, calendar: Calendar = .current) -> Holiday? {
        let today = MonthDay(date: date, calendar: calendar)
        return allCases.first { $0.season.contains(today) }
    }

    var displayTitle: String {
        switch self {
        case .halloween:
            L10n.halloween
        case .christmas:
            L10n.christmas
        }
    }

    /// TMDB keywords, which Jellyfin imports as tags. Kept narrow on purpose:
    /// broader keywords like "ghost", "witch" or "holiday" mostly match unrelated titles.
    var tags: [ItemTag] {
        switch self {
        case .halloween:
            ["halloween", "halloween party", "haunted house", "haunting"]
        case .christmas:
            ["christmas", "christmas eve", "xmas eve", "christmas party", "christmas tree", "santa claus"]
        }
    }

    private var season: ClosedRange<MonthDay> {
        switch self {
        case .halloween:
            MonthDay(month: 10, day: 1) ... MonthDay(month: 10, day: 31)
        case .christmas:
            MonthDay(month: 12, day: 1) ... MonthDay(month: 12, day: 26)
        }
    }
}

private struct MonthDay: Comparable {

    let month: Int
    let day: Int

    init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        self.init(
            month: calendar.component(.month, from: date),
            day: calendar.component(.day, from: date)
        )
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.month, lhs.day) < (rhs.month, rhs.day)
    }
}
