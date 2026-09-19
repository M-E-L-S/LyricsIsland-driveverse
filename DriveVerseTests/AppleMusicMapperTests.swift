import Testing
import Foundation
@testable import DriveVerse

@Suite struct AppleMusicMapperTests {
    private let at = Date(timeIntervalSinceReferenceDate: 750_000_000)

    @Test func nilSnapshotMapsToNil() {
        // No now-playing item is available from Apple Music.
        #expect(AppleMusicStateMapper.state(from: nil, capturedAt: at) == nil)
    }

    @Test func missingTitleMapsToNil() {
        let snapshot = AppleMusicSnapshot(
            title: nil, artist: "A", album: nil,
            durationSec: 100, positionSec: 5, isPlaying: true
        )
        #expect(AppleMusicStateMapper.state(from: snapshot, capturedAt: at) == nil)
    }

    @Test func fullMapping() {
        let artwork = Data([1, 2, 3])
        let snapshot = AppleMusicSnapshot(
            title: "Karma Police", artist: "Radiohead", album: "OK Computer",
            artworkData: artwork,
            durationSec: 261.5, positionSec: 42.25, isPlaying: true
        )
        let state = AppleMusicStateMapper.state(from: snapshot, capturedAt: at)
        #expect(state == NowPlayingState(
            title: "Karma Police", artist: "Radiohead", album: "OK Computer",
            artworkData: artwork,
            durationMs: 261_500, positionMs: 42_250,
            isPlaying: true, capturedAt: at
        ))
    }

    @Test func nanPositionBecomesZero() {
        let snapshot = AppleMusicSnapshot(
            title: "T", artist: "A", album: nil,
            durationSec: 100, positionSec: .nan, isPlaying: false
        )
        #expect(AppleMusicStateMapper.state(from: snapshot, capturedAt: at)?.positionMs == 0)
    }

    @Test func zeroDurationBecomesNil() {
        let snapshot = AppleMusicSnapshot(
            title: "T", artist: "A", album: nil,
            durationSec: 0, positionSec: 1, isPlaying: true
        )
        #expect(AppleMusicStateMapper.state(from: snapshot, capturedAt: at)?.durationMs == nil)
    }

    @Test func missingArtistBecomesEmpty() {
        let snapshot = AppleMusicSnapshot(
            title: "T", artist: nil, album: nil,
            durationSec: 100, positionSec: 1, isPlaying: true
        )
        #expect(AppleMusicStateMapper.state(from: snapshot, capturedAt: at)?.artist == "")
    }
}
