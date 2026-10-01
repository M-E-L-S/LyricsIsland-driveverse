import Foundation

enum LiveLyricsLineEffect: String, Codable, CaseIterable, Identifiable {
    case original
    case particles

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .original: return "Original effect"
        case .particles: return "Particle effect"
        }
    }
}

/// Only the visible lyric/index can replace a particle cloud. Metadata,
/// image refreshes, position ticks and marquee phases keep this identity stable.
struct LiveLyricsParticleLineIdentity: Hashable {
    let lineIndex: Int?
    let text: String
}

/// Shared timing keeps line presentation and the first fill update in order.
enum LiveLyricsAnimationTiming {
    static let lineTransitionDuration: TimeInterval = 0.35
    static let particleDisperseDuration: TimeInterval = 0.4
    static let particleGatherDelay: TimeInterval = particleDisperseDuration + 0.02
    static let particleGatherDuration: TimeInterval = 0.65
    static let particleStaggerStep: TimeInterval = 0.012

    // Activity.update completion is not a display acknowledgement. Leave a
    // short render allowance after the transition before sending its endpoint.
    static let lineFillStartDelay: TimeInterval = lineTransitionDuration + 0.15
}

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
        /// Pre-rendered text segments. Their joined text stays unchanged during
        /// a line; planned mask endpoints advance independently of sync ticks.
        var completedText: String
        var activeText: String
        var remainingText: String
        /// Anchor the active word to playback time so the lock screen can
        /// reveal its glyphs without sending an Activity update per frame.
        var lyricPositionMs: Int
        var positionDate: Date
        var activeWordStartMs: Int
        var activeWordEndMs: Int
        /// Target position in displayed characters. At archive time the widget
        /// converts this to a geometric mask endpoint for native interpolation.
        var fillTarget: Double
        var fillAnimationDurationMs: Int
        /// Compact-island marquee metadata. The line index restarts a
        /// one-shot animation even when two adjacent lyric lines are equal.
        var lineIndex: Int?
        var usesWordTiming: Bool
        /// Line-only compact marquee phase. A second Activity update advances
        /// this because widget-local state is archived before it is rendered.
        var lineMarqueeAtEnd: Bool
        /// Duration of the compact line animation, adapted to the remaining
        /// time before the next lyric line replaces it.
        var lineMarqueeDurationMs: Int
        var isPlaying: Bool
        /// Optional for activities archived before the effect selector existed.
        /// A missing preference preserves the original text presentation.
        var lineEffect: LiveLyricsLineEffect? = nil
        var particleLineIdentity: LiveLyricsParticleLineIdentity {
            LiveLyricsParticleLineIdentity(
                lineIndex: lineIndex,
                text: completedText + activeText + remainingText
            )
        }

        var usesLineParticles: Bool {
            lineEffect == .particles && !usesWordTiming
                && lineIndex != nil && !completedText.isEmpty
        }

        private enum CodingKeys: String, CodingKey {
            case title = "t"
            case artist = "a"
            case artworkData = "i"
            case secondaryLine = "s"
            case nextLine = "n"
            case completedText = "d"
            case activeText = "v"
            case remainingText = "m"
            case lyricPositionMs = "p"
            case positionDate = "q"
            case activeWordStartMs = "b"
            case activeWordEndMs = "f"
            case fillTarget = "g"
            case fillAnimationDurationMs = "h"
            case lineIndex = "l"
            case usesWordTiming = "w"
            case lineMarqueeAtEnd = "e"
            case lineMarqueeDurationMs = "r"
            case isPlaying = "x"
            case lineEffect = "j"
        }
    }
}
#endif
