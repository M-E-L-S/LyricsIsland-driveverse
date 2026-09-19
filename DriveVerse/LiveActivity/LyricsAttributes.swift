import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared between the app target and the widget extension.
/// Keep ContentState tiny — it is serialized on every Activity.update.
///
/// There are deliberately no fixed attributes: one activity spans a whole
/// listening session (iOS refuses Activity.request from a backgrounded app,
/// so per-track activities would vanish on every backgrounded song change).
/// Everything, including the track metadata, must be updatable.
struct LyricsAttributes: ActivityAttributes {
    struct Word: Codable, Hashable {
        var text: String
        var startTimeMs: Int
        var endTimeMs: Int

        private enum CodingKeys: String, CodingKey {
            case text = "t"
            case startTimeMs = "s"
            case endTimeMs = "e"
        }
    }

    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var artworkData: Data?
        var currentLine: String
        var secondaryLine: String
        var nextLine: String
        var currentWords: [Word]
        /// Anchors local word/progress animation without extra Activity updates.
        var trackPositionMs: Int
        var lyricPositionMs: Int
        var playbackReferenceDate: Date
        var durationMs: Int?
        /// 0–1 progress through the whole track.
        var progress: Double
        var isPlaying: Bool

        private enum CodingKeys: String, CodingKey {
            case title = "t"
            case artist = "a"
            case artworkData = "i"
            case currentLine = "c"
            case secondaryLine = "s"
            case nextLine = "n"
            case currentWords = "w"
            case trackPositionMs = "p"
            case lyricPositionMs = "l"
            case playbackReferenceDate = "r"
            case durationMs = "d"
            case progress = "g"
            case isPlaying = "x"
        }
    }
}
#endif
