import Foundation

struct NowPlayingState: Equatable {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?
    let positionMs: Int
    let isPlaying: Bool
    /// When `positionMs` was observed — the sync engine extrapolates from here.
    let capturedAt: Date

    func with(isPlaying: Bool) -> NowPlayingState {
        NowPlayingState(
            title: title, artist: artist, album: album,
            durationMs: durationMs, positionMs: positionMs,
            isPlaying: isPlaying, capturedAt: capturedAt
        )
    }

    /// Same logical track (ignoring position/playback flags).
    func isSameTrack(as other: NowPlayingState) -> Bool {
        title == other.title && artist == other.artist
    }
}
