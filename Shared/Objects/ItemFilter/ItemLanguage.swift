//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import OrderedCollections

/// A language filter, keyed by its ISO 639-2/T code when the server's value is an ISO 639 code.
///
/// Servers list every code they have stored, so synonyms such as `fre`, `fra`
/// and `fr` become a single French filter that matches each of them.
struct ItemLanguage: Codable, Hashable, ItemFilter {

    /// ISO 639-2 bibliographic codes and their terminology equivalents
    private static let terminologyCodes: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    let displayTitle: String
    let value: String

    /// Every code the server may have stored for this language
    var codes: [String] {
        guard let code = Self.terminologyCode(for: value) else { return [value] }

        let bibliographicCode = Self.terminologyCodes.first { $0.value == code }?.key

        return OrderedSet([code, bibliographicCode, Locale.LanguageCode(code).identifier(.alpha2)].compactMap(\.self)).elements
    }

    init(displayTitle: String, value: String) {
        self.displayTitle = displayTitle
        self.value = value
    }

    init(from anyFilter: AnyItemFilter) {
        self.displayTitle = anyFilter.displayTitle
        self.value = anyFilter.value
    }

    init?(_ nameValuePair: NameValuePair) {
        guard let name = nameValuePair.name, let value = nameValuePair.value else { return nil }

        if let code = Self.terminologyCode(for: value) {
            // Server names repeat the code, such as "French (fre)", so prefer the localized name.
            self.displayTitle = Locale.current.localizedString(forLanguageCode: code) ?? name
            self.value = code
        } else {
            self.displayTitle = name
            self.value = value
        }
    }

    /// The ISO 639-2/T code for an ISO 639-1 or ISO 639-2 code
    private static func terminologyCode(for code: String) -> String? {
        Locale.LanguageCode(terminologyCodes[code] ?? code).identifier(.alpha3)
    }
}
