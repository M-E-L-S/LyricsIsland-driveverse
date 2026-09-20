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
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var artworkData: Data?
        var secondaryLine: String
        var nextLine: String
        /// Pre-rendered word segments. Live Activities do not reliably redraw
        /// TimelineView at sub-second intervals, so the app advances these via
        /// Activity updates whenever the active word changes.
        var completedText: String
        var activeText: String
        var remainingText: String
        /// Compact-island marquee metadata. The line index restarts a
        /// one-shot animation even when two adjacent lyric lines are equal;
        /// word timing selects short, state-driven animation segments.
        var lineIndex: Int?
        var usesWordTiming: Bool
        /// Line-only compact marquee phase. A second Activity update advances
        /// this because widget-local state is archived before it is rendered.
        var lineMarqueeAtEnd: Bool
        var isPlaying: Bool

        private enum CodingKeys: String, CodingKey {
            case title = "t"
            case artist = "a"
            case artworkData = "i"
            case secondaryLine = "s"
            case nextLine = "n"
            case completedText = "d"
            case activeText = "v"
            case remainingText = "m"
            case lineIndex = "l"
            case usesWordTiming = "w"
            case lineMarqueeAtEnd = "e"
            case isPlaying = "x"
        }
    }
}
#endif
