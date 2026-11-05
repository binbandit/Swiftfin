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
import MediaAccessibility
import MediaAccessibilityKit

/// System accessibility preferences augment server defaults, but explicit track choices always take precedence.
struct MediaPlaybackPreferences {

    var captions: CaptionPreferences
    var audio: AudibleMediaPreferences
    var languages: [String] = Locale.preferredLanguages
    var subtitleChoice: SubtitleChoice?

    static var current: Self {
        Self(captions: .current, audio: .current, subtitleChoice: .remembered)
    }

    struct Selection: Equatable {

        var audio: Int?
        var subtitle: Int?
    }

    func selection(in source: MediaSourceInfo, audio explicitAudio: Int? = nil, subtitle explicitSubtitle: Int? = nil) -> Selection {
        let streams = source.mediaStreams ?? []
        let audioStreams = streams.filter { $0.type == .audio && $0.isExternal != true && ($0.index ?? -1) >= 0 }
        let subtitles = streams.filter { $0.type == .subtitle && $0.deliveryMethod != .drop && ($0.index ?? -1) >= 0 }
        let defaultAudio = audioStreams.first(property: \.index, equalTo: source.defaultAudioStreamIndex)

        // Wait for the server's language choice when its default audio index is not available yet.
        let preferredAudio = defaultAudio.flatMap { preferredAudio(in: audioStreams, default: $0) }
        let audioIndex = explicitAudio ?? preferredAudio?.index ?? source.defaultAudioStreamIndex
        let audioLanguage = audioStreams.first(property: \.index, equalTo: audioIndex)?.language

        return Selection(
            audio: audioIndex,
            subtitle: explicitSubtitle ?? preferredSubtitle(
                in: subtitles, defaultIndex: source.defaultSubtitleStreamIndex, audioLanguage: audioLanguage
            )
        )
    }

    private func preferredAudio(in streams: [MediaStream], default fallback: MediaStream?) -> MediaStream? {
        guard audio.preferredCharacteristics.contains(MAMediaCharacteristicDescribesVideoForAccessibility as String) else {
            return nil
        }

        let preferredLanguages = fallback?.language.map { [$0] } ?? languages
        let candidates = streams.filter { $0.hasAudioDescriptionLabel && languageRank($0.language, in: preferredLanguages) != nil }

        return best(in: candidates, languages: preferredLanguages, defaultIndex: fallback?.index)
    }

    func subtitleForReplay(in streams: [MediaStream], defaultIndex: Int?) -> Int? {
        let fullCaptions = streams.filter { $0.isForced != true }

        return best(
            in: fullCaptions.isEmpty ? streams : fullCaptions,
            languages: captions.selectedLanguages.isEmpty ? languages : captions.selectedLanguages,
            defaultIndex: defaultIndex
        )?.index
    }

    private func preferredSubtitle(in streams: [MediaStream], defaultIndex: Int?, audioLanguage: String?) -> Int? {
        // Missing stream metadata can be filled by the playback-info response. Leave negotiation to the server.
        guard streams.isNotEmpty else { return subtitleChoice == .off ? -1 : defaultIndex }

        let preferredLanguages = captions.selectedLanguages.isEmpty ? languages : captions.selectedLanguages
        let forced = streams.filter { $0.isForced == true }
        let forcedLanguages = audioLanguage.map { [$0] } ?? preferredLanguages

        let forcedIndex = best(
            in: forced.filter { languageRank($0.language, in: forcedLanguages) != nil },
            languages: forcedLanguages, defaultIndex: defaultIndex
        )?.index ?? -1

        func automaticSubtitle() -> Int? {
            switch captions.displayType {
            case .forcedOnly:
                return forcedIndex

            case .alwaysOn:
                return best(in: streams.filter { $0.isForced != true }, languages: preferredLanguages, defaultIndex: defaultIndex)?.index
                    ?? forcedIndex

            case .automatic:
                // Honor the account's subtitle mode and remembered selections when it provides a track.
                if let defaultIndex, streams.contains(where: { $0.index == defaultIndex }) {
                    return defaultIndex
                }

                guard let audioLanguage, let primaryLanguage = preferredLanguages.first,
                      let audioCode = Self.languageCode(audioLanguage), let preferredCode = Self.languageCode(primaryLanguage)
                else { return defaultIndex }
                guard audioCode != preferredCode else { return forcedIndex }

                let candidates = streams.filter { $0.isForced != true && languageRank($0.language, in: preferredLanguages) != nil }
                return best(in: candidates, languages: preferredLanguages, defaultIndex: defaultIndex)?.index ?? forcedIndex

            case .unknown:
                return defaultIndex
            }
        }

        switch subtitleChoice {
        case nil:
            return automaticSubtitle()

        case .off:
            // Forced subtitles translate foreign dialogue and signs, so they still show, as with Off in the TV app.
            return forcedIndex

        case let .on(language, hearingImpaired):
            let languages = language.map { [$0] } ?? preferredLanguages
            let candidates = streams.filter { $0.isForced != true && languageRank($0.language, in: languages) != nil }

            if let stream = best(in: candidates, languages: languages, defaultIndex: defaultIndex, hearingImpaired: hearingImpaired) {
                return stream.index
            }

            // Without that language, choose as usual, but never full subtitles in a language the user hasn't asked for.
            let index = automaticSubtitle()

            guard let stream = streams.first(property: \.index, equalTo: index), stream.isForced != true,
                  stream.language.flatMap(Self.languageCode) != nil, languageRank(stream.language, in: preferredLanguages) == nil
            else { return index }

            return forcedIndex
        }
    }

    /// `hearingImpaired` asks for subtitles of that kind. Without it, accessibility settings can ask for SDH.
    private func best(
        in streams: [MediaStream],
        languages: [String],
        defaultIndex: Int?,
        hearingImpaired: Bool? = nil
    ) -> MediaStream? {
        let prefersSDH = captions.displayType == .alwaysOn || captions.preferredCharacteristics.contains {
            $0 == MAMediaCharacteristicTranscribesSpokenDialogForAccessibility as String
                || $0 == MAMediaCharacteristicDescribesMusicAndSoundForAccessibility as String
        }
        // nil prefers neither SDH nor regular subtitles.
        let wantsSDH = hearingImpaired ?? (prefersSDH ? true : nil)

        return streams.enumerated()
            .min { lhs, rhs in
                func rank(_ stream: MediaStream, offset: Int) -> [Int] {
                    [
                        languageRank(stream.language, in: languages) ?? Int.max,
                        stream.type == .subtitle && wantsSDH == (stream.isHearingImpaired == true) ? 0 : 1,
                        stream.index == defaultIndex ? 0 : 1,
                        stream.isDefault == true ? 0 : 1,
                        offset
                    ]
                }

                return rank(lhs.element, offset: lhs.offset).lexicographicallyPrecedes(rank(rhs.element, offset: rhs.offset))
            }?.element
    }

    private func languageRank(_ language: String?, in preferences: [String]) -> Int? {
        guard let language, let code = Self.languageCode(language) else { return nil }

        for (index, preference) in preferences.enumerated() {
            if Locale.canonicalLanguageIdentifier(from: language) == Locale.canonicalLanguageIdentifier(from: preference) {
                return index * 2
            }

            if code == Self.languageCode(preference) {
                return index * 2 + 1
            }
        }

        return nil
    }

    private static func languageCode(_ identifier: String) -> String? {
        let code = Locale.Language(identifier: identifier).languageCode
        guard let code, code.identifier != "und", code.identifier != "zxx" else { return nil }

        // Jellyfin uses ISO 639-2 codes while Apple normally supplies BCP-47 identifiers.
        return code.identifier(.alpha2) ?? code.identifier(.alpha3)
    }
}

extension MediaPlaybackPreferences {

    /// The subtitles last picked by hand, which later playback starts with.
    /// A language rather than a stream index, because indexes only identify tracks within one file.
    enum SubtitleChoice: Hashable, Storable {

        /// No full subtitles. Forced subtitles in the audio's language still show.
        case off
        /// `language` is nil for a track without one, which then stands for the preferred languages.
        case on(language: String?, hearingImpaired: Bool)

        /// Picking a forced track asks for only foreign dialogue to be translated, which is what Off shows.
        init?(index: Int, in streams: [MediaStream]) {
            guard index >= 0 else {
                self = .off
                return
            }
            guard let stream = streams.first(where: { $0.type == .subtitle && $0.index == index }) else { return nil }

            if stream.isForced == true {
                self = .off
            } else {
                let language = stream.language.flatMap { MediaPlaybackPreferences.languageCode($0) == nil ? nil : $0 }
                self = .on(language: language, hearingImpaired: stream.isHearingImpaired == true)
            }
        }

        /// The current user's choice, when their account remembers subtitle selections.
        static var remembered: Self? {
            guard Container.shared.currentUserSession()?.user.data.configuration?.isRememberSubtitleSelections == true
            else { return nil }

            return StoredValues[.User.subtitleChoice]
        }

        /// Remembers the subtitle track at `index`, or Off for -1.
        static func remember(_ index: Int, in streams: [MediaStream]) {
            guard let choice = Self(index: index, in: streams) else { return }

            StoredValues[.User.subtitleChoice] = choice
        }
    }
}

extension MediaStream {

    /// The SDK has no audio-description disposition. Use explicit metadata labels, never commentary or hearing-impaired flags.
    var hasAudioDescriptionLabel: Bool {
        [title, displayTitle].compactMap(\.self).contains {
            $0.range(
                of: #"\b(audio[ -]?description[s]?|audio[ -]?described|descriptive[ -]?audio|described[ -]?video)\b|(?:^|[\[(]| - )(?:AD|DVS)(?:$|[\])]| - )"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }
}
