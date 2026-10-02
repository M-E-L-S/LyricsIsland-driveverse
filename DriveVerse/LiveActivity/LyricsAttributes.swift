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

/// Only the visible lyric can replace a particle cloud. Metadata,
/// image refreshes, position ticks and marquee phases keep this identity stable.
struct LiveLyricsParticleLineIdentity: Hashable {
    let text: String
}

/// Shared timing keeps line presentation and the first fill update in order.
enum LiveLyricsAnimationTiming {
    static let lineTransitionDuration: TimeInterval = 0.35

    // Activity.update completion is not a display acknowledgement. Leave a
    // short render allowance after the transition before sending its endpoint.
    static let lineFillStartDelay: TimeInterval = lineTransitionDuration + 0.15

    /// Advance only the line lookup; word timing continues on the audio clock.
    static func lineTriggerLeadMs(wordUpdatesEnabled: Bool,
                                  lineEffect: LiveLyricsLineEffect) -> Int {
        if !wordUpdatesEnabled && lineEffect == .particles {
            // Start 200 ms later; keep the particle spring itself unchanged.
            return 1_150
        }
        return Int(((lineTransitionDuration + 0.15) * 1_000).rounded())
    }
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
        /// One revision per actual text change, preserved across all other
        /// Activity updates. Only the first update may start its point morph.
        var particleMorphRevision: Int? = nil
        var particleMorphEnabled: Bool? = nil
        /// Source glyphs for the insertion displacement. The existing
        /// nextLine supplies the outgoing destination before it is removed.
        var particlePreviousText: String? = nil
        var particleLineIdentity: LiveLyricsParticleLineIdentity {
            LiveLyricsParticleLineIdentity(
                text: completedText + activeText + remainingText
            )
        }

        mutating func applyParticleMorph(_ plan: LiveLyricsParticleMorphPlan) {
            particleMorphRevision = plan.revision
            particleMorphEnabled = plan.animates
            particlePreviousText = plan.previousText
        }

        mutating func stopParticleMorph() {
            particleMorphEnabled = false
            particlePreviousText = nil
        }

        /// Adding morph context must not make an otherwise valid Activity
        /// payload exceed its limit. Keep the current lyric readable if an
        /// unusually large Unicode line leaves no room for source geometry.
        mutating func boundParticleContext() {
            guard particlePreviousText != nil,
                  let bytes = try? JSONEncoder().encode(self), bytes.count > 4_000 else { return }
            stopParticleMorph()
        }

        /// Build the two ends from what was actually submitted, rather than
        /// from an intermediate sync tick which might have been superseded.
        /// A returned state refreshes the old lyric's destination only.
        mutating func prepareParticleTransition(from previous: Self?) -> Self? {
            guard usesLineParticles else { return nil }
            particleMorphEnabled = previous?.usesLineParticles == true
                && previous?.particleLineIdentity != particleLineIdentity && isPlaying
            particlePreviousText = particleMorphEnabled == true ? previous?.particleLineIdentity.text : nil
            boundParticleContext()
            guard particleMorphEnabled == true, var prepared = previous,
                  prepared.nextLine != particleLineIdentity.text else { return nil }
            prepared.nextLine = particleLineIdentity.text
            prepared.stopParticleMorph()
            guard let bytes = try? JSONEncoder().encode(prepared), bytes.count <= 4_000 else {
                stopParticleMorph()
                return nil
            }
            return prepared
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
            case particleMorphRevision = "u"
            case particleMorphEnabled = "y"
            case particlePreviousText = "z"
        }
    }
}
#endif
