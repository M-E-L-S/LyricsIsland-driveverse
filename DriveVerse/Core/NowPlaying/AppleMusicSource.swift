import Foundation
import Combine

enum MediaAuthStatus: Equatable {
    case unknown
    case authorized
    case denied
}

/// Plain snapshot of MPMusicPlayerController state — lets the mapping be pure
/// and unit-testable with fakes (MediaPlayer itself needs a real device).
struct AppleMusicSnapshot: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data? = nil
    var durationSec: Double
    var positionSec: Double
    var isPlaying: Bool
}

enum AppleMusicStateMapper {
    static func state(from snapshot: AppleMusicSnapshot?, capturedAt: Date) -> NowPlayingState? {
        guard let snapshot, let title = snapshot.title, !title.isEmpty else { return nil }
        let durationMs = (snapshot.durationSec.isFinite && snapshot.durationSec > 0)
            ? Int(snapshot.durationSec * 1000) : nil
        let positionMs = (snapshot.positionSec.isFinite && snapshot.positionSec > 0)
            ? Int(snapshot.positionSec * 1000) : 0
        return NowPlayingState(
            title: title,
            artist: snapshot.artist ?? "",
            album: snapshot.album,
            artworkData: snapshot.artworkData,
            durationMs: durationMs,
            positionMs: positionMs,
            isPlaying: snapshot.isPlaying,
            capturedAt: capturedAt
        )
    }
}

#if os(iOS)
import MediaPlayer
import UIKit

/// Observes the system (Apple Music) player via the MediaPlayer framework.
/// Provides local playback state with exact position and no polling delay.
/// Emits nil when Apple Music has no now-playing item. No MusicKit or
/// developer token is required for playback observation.
final class AppleMusicSource {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    let authStatusSubject = CurrentValueSubject<MediaAuthStatus, Never>(.unknown)

    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var started = false
    private var artworkCacheKey: String?
    private var artworkCacheData: Data?

    func start() {
        guard !started else { return }
        started = true
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            authStatusSubject.send(.authorized)
            beginObserving()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if status == .authorized {
                        self.authStatusSubject.send(.authorized)
                        self.beginObserving()
                    } else {
                        self.authStatusSubject.send(.denied)
                        self.subject.send(nil)
                    }
                }
            }
        default:
            authStatusSubject.send(.denied)
            subject.send(nil)
        }
    }

    func stop() {
        guard started else { return }
        started = false
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        lastSnapshot = nil
        artworkCacheKey = nil
        artworkCacheData = nil
        player.endGeneratingPlaybackNotifications()
    }

    private func beginObserving() {
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name: Notification.Name in [
            .MPMusicPlayerControllerNowPlayingItemDidChange,
            .MPMusicPlayerControllerPlaybackStateDidChange,
        ] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                self?.emit()
            })
        }
        // 1 s poll of the full player state — MediaPlayer notifications are
        // flaky while backgrounded (Drive Mode), so track switches and
        // pauses must also be caught by polling, not notifications alone.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.emit()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        emit()
    }

    /// Foreground resync: read the player immediately instead of waiting for
    /// the next tick or a notification that may never have arrived.
    func refresh() {
        guard timer != nil else { return }
        emit()
    }

    func togglePlayback() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refreshAfterControl()
    }

    func skipToPreviousItem() {
        player.skipToPreviousItem()
        refreshAfterControl()
    }

    func skipToNextItem() {
        player.skipToNextItem()
        refreshAfterControl()
    }

    func seek(toFraction fraction: Double) {
        guard let item = player.nowPlayingItem, item.playbackDuration > 0 else { return }
        player.currentPlaybackTime = min(1, max(0, fraction)) * item.playbackDuration
        refreshAfterControl()
    }

    func seek(bySeconds offset: Double) {
        let duration = player.nowPlayingItem?.playbackDuration ?? 0
        let target = max(0, player.currentPlaybackTime + offset)
        player.currentPlaybackTime = duration > 0 ? min(duration, target) : target
        refreshAfterControl()
    }

    private func refreshAfterControl() {
        emit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.emit()
        }
    }

    private var lastSnapshot: AppleMusicSnapshot??

    private func emit() {
        let snapshot = player.nowPlayingItem.map { item in
            let artworkKey = "\(item.persistentID)|\(item.title ?? "")|\(item.albumTitle ?? "")"
            if artworkKey != artworkCacheKey {
                artworkCacheKey = artworkKey
                artworkCacheData = Self.compactArtworkData(item.artwork)
            }
            AppleMusicSnapshot(
                title: item.title,
                artist: item.artist,
                album: item.albumTitle,
                artworkData: artworkCacheData,
                durationSec: item.playbackDuration,
                positionSec: player.currentPlaybackTime,
                isPlaying: player.playbackState == .playing
            )
        }
        // While playing the position advances every tick, so this always
        // sends; while paused or idle it collapses the 1 s tick to real
        // changes only, keeping the UI and sync pipeline quiet.
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        subject.send(AppleMusicStateMapper.state(from: snapshot, capturedAt: Date()))
    }

    /// ActivityKit's complete dynamic state must stay below 4 KB. A tiny JPEG
    /// leaves room for lyrics, word timings, and playback metadata.
    private static func compactArtworkData(_ artwork: MPMediaItemArtwork?) -> Data? {
        guard let artwork else { return nil }
        let sides: [CGFloat] = [36, 32]
        let qualities: [CGFloat] = [0.6, 0.4, 0.25, 0.15]
        for side in sides {
            let size = CGSize(width: side, height: side)
            guard let source = artwork.image(at: size) else { continue }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in qualities {
                if let data = image.jpegData(compressionQuality: quality), data.count <= 900 {
                    return data
                }
            }
        }
        return nil
    }
}
#endif
