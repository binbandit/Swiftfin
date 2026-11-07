//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import Observation

@MainActor
@Observable
final class MediaSegmentObserver: MediaSessionObserver, VideoPlayerOverlayActionProviding {

    typealias Loader = @MainActor (String, UserSession) async throws -> [MediaSegmentDto]

    let id = "mediaSegments"
    private weak var item: MediaPlayerItem?
    private let load: Loader
    private weak var mediaSession: MediaSession?
    private(set) var segments: [MediaSegment] = []

    /// The segment that can be skipped now. It changes only when playback crosses a segment boundary,
    /// so the controls reading `overlayActions` don't redraw, and rebuild their open menus, every frame.
    private var activeSegment: MediaSegment?

    /// Segments skipped or played past, which stay hidden until playback returns before their start.
    @ObservationIgnored
    private var passedSegmentIDs: Set<String> = []

    @ObservationIgnored
    private var request: AnyCancellable?
    @ObservationIgnored
    private var positionObservation: ObservationToken?

    init(load: @escaping Loader = { itemID, session in
        try await session.send(Paths.getItemSegments(itemID: itemID)).value.items ?? []
    }) {
        self.load = load
    }

    func observe(_ mediaSession: MediaSession) -> AnyCancellable {
        self.mediaSession = mediaSession
        item = mediaSession.playbackItem

        if let item, !item.baseItem.isLiveStream, item.baseItem.mediaType != .audio,
           let itemID = item.baseItem.id
        {
            let session = mediaSession.userSession

            request = Task { [weak self, weak item, load] in
                do {
                    let values = try await load(itemID, session)
                    guard !Task.isCancelled, let self, let item, self.mediaSession?.playbackItem === item else { return }

                    segments = MediaSegment.segments(from: values, itemID: itemID)

                    if let position = self.mediaSession?.seconds {
                        updateSegments(at: position)
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    self?.mediaSession?.logger.debug("Media segments unavailable: \(error.localizedDescription)")
                }
            }
            .asAnyCancellable()

            positionObservation = ObservationToken { [weak mediaSession] in
                mediaSession?.seconds
            } onChange: { [weak self] position in
                if let position {
                    self?.updateSegments(at: position)
                }
            }
        }

        return AnyCancellable { [self] in
            MainActor.assumeIsolated {
                request = nil
                positionObservation = nil
                segments = []
                passedSegmentIDs = []
                activeSegment = nil
                self.mediaSession = nil
                item = nil
            }
        }
    }

    private func updateSegments(at position: Duration) {
        passedSegmentIDs = Set(
            segments
                .filter { position >= $0.end || (position >= $0.start && passedSegmentIDs.contains($0.id)) }
                .map(\.id)
        )

        let duration = mediaSession?.playbackState.duration ?? mediaSession?.item.runtime
        let segment = mediaSession?.canSeek == true ? segments.first {
            !passedSegmentIDs.contains($0.id) && $0.skipTarget(at: position, duration: duration) != nil
        } : nil

        if segment?.id != activeSegment?.id {
            activeSegment = segment
        }
    }

    /// The episode autoplay plays after this one, when autoplay is on.
    private static func autoPlayEpisode(after mediaSession: MediaSession) -> PlaybackIntent? {
        guard mediaSession.userSession.user.data.configuration?.enableNextEpisodeAutoPlay == true,
              let next = mediaSession.queue?.nextItem, next.item.type == .episode else { return nil }

        return next
    }

    var overlayActions: [VideoPlayerOverlayAction] {
        guard let mediaSession, let item, mediaSession.playbackItem === item,
              mediaSession.state == .playback, !mediaSession.isSeeking,
              let segment = activeSegment, let title = segment.skipTitle else { return [] }

        // During the credits, start the next episode as autoplay would, rather than seeking to the end first.
        if segment.type == .outro, let next = Self.autoPlayEpisode(after: mediaSession) {
            return [VideoPlayerOverlayAction(
                id: segment.id,
                title: L10n.nextEpisode,
                systemImage: "forward.end.fill",
                preview: next.item
            ) { [
                weak self,
                weak item
            ] in
                guard let self, let mediaSession = self.mediaSession, let item, self.item === item,
                      mediaSession.playbackItem === item, mediaSession.state == .playback,
                      let next = Self.autoPlayEpisode(after: mediaSession) else { return }

                mediaSession.playNewItem(intent: next)
            }]
        }

        return [VideoPlayerOverlayAction(id: segment.id, title: title, systemImage: "forward.end.fill") { [
            weak self,
            weak item
        ] in
            guard let self, let mediaSession = self.mediaSession, let item, self.item === item,
                  mediaSession.playbackItem === item, mediaSession.state == .playback, mediaSession.canSeek, !mediaSession.isSeeking,
                  let target = segment.skipTarget(
                      at: mediaSession.seconds,
                      duration: mediaSession.playbackState.duration ?? mediaSession.item.runtime
                  ) else { return }

            // A seek can land just short of the target, which must not bring the button back.
            passedSegmentIDs.insert(segment.id)
            activeSegment = nil
            mediaSession.seek(to: target)
        }]
    }
}
