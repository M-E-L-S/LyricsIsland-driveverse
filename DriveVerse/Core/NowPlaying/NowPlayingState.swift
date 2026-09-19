import Foundation

struct NowPlayingState: Equatable {
    let title: String
    let artist: String
    let album: String?
    /// Small JPEG thumbnail suitable for the Live Activity payload.
    let artworkData: Data?
    let durationMs: Int?
    let positionMs: Int
    let isPlaying: Bool
    /// When `positionMs` was observed — the sync engine extrapolates from here.
    let capturedAt: Date

    init(
        title: String,
        artist: String,
        album: String?,
        artworkData: Data? = nil,
        durationMs: Int?,
        positionMs: Int,
        isPlaying: Bool,
        capturedAt: Date
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.durationMs = durationMs
        self.positionMs = positionMs
        self.isPlaying = isPlaying
        self.capturedAt = capturedAt
    }

    func with(isPlaying: Bool) -> NowPlayingState {
        NowPlayingState(
            title: title, artist: artist, album: album, artworkData: artworkData,
            durationMs: durationMs, positionMs: positionMs,
            isPlaying: isPlaying, capturedAt: capturedAt
        )
    }

    /// Same logical track (ignoring position/playback flags).
    func isSameTrack(as other: NowPlayingState) -> Bool {
        title == other.title && artist == other.artist
    }
}
