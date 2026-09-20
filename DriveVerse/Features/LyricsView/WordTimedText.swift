import Foundation
import SwiftUI

/// Karaoke-style word highlighting driven locally from the playback anchor.
/// It doesn't require mutating the cached lyric or polling a provider.
struct WordTimedText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let line: LyricsLine
    let playback: NowPlayingState
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    var completedColor: Color = .primary
    var activeColor: Color = .accentColor
    var pendingColor: Color = .secondary.opacity(0.45)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playback.isPlaying)) { timeline in
            let state = renderState(at: timeline.date)
            ZStack(alignment: .topLeading) {
                Text(state.base)

                if state.hasActiveWord {
                    // The three identical masks create the soft bloom Apple
                    // Music uses around the word currently being sung. Clear
                    // glyphs preserve exactly the same wrapping as the base.
                    Text(state.glowMask)
                        .blur(radius: 9)
                        .opacity(glowIntensity(state.progress) * 0.52)
                        .blendMode(.plusLighter)
                        .accessibilityHidden(true)
                    Text(state.glowMask)
                        .blur(radius: 3)
                        .opacity(glowIntensity(state.progress) * 0.70)
                        .blendMode(.plusLighter)
                        .accessibilityHidden(true)
                    Text(state.glowMask)
                        .opacity(glowIntensity(state.progress) * 0.30)
                        .blendMode(.plusLighter)
                        .accessibilityHidden(true)
                }
            }
            .compositingGroup()
        }
    }

    private func renderState(at date: Date) -> WordGlowRenderState {
        guard let words = line.words, !words.isEmpty else {
            return WordGlowRenderState(
                base: AttributedString(LyricsTextRenderer.primary(for: line, options: options)),
                glowMask: AttributedString(),
                progress: 0,
                hasActiveWord: false
            )
        }
        let position = SyncEngine.extrapolatedPositionMs(anchor: playback, at: date) - timingOffsetMs
        var base = AttributedString()
        var glowMask = AttributedString()
        var activeProgress = 0.0
        var hasActiveWord = false

        for word in words {
            let renderedWord = ChineseTextConverter.convert(
                word.original,
                using: options.chineseConversion
            )
            var part = AttributedString(renderedWord)
            var glowPart = AttributedString(renderedWord)

            if position >= word.endTimeMs {
                part.foregroundColor = completedColor
            } else if position >= word.startTimeMs {
                part.foregroundColor = activeColor
                glowPart.foregroundColor = .white
                let duration = max(1, word.endTimeMs - word.startTimeMs)
                activeProgress = min(1, max(
                    0,
                    Double(position - word.startTimeMs) / Double(duration)
                ))
                hasActiveWord = true
            } else {
                part.foregroundColor = pendingColor
            }

            if position < word.startTimeMs || position >= word.endTimeMs {
                glowPart.foregroundColor = .clear
            }
            base.append(part)
            glowMask.append(glowPart)
        }

        return WordGlowRenderState(
            base: base,
            glowMask: glowMask,
            progress: activeProgress,
            hasActiveWord: hasActiveWord
        )
    }

    private func glowIntensity(_ progress: Double) -> Double {
        guard !reduceMotion else { return 0.82 }
        // Ease the bloom in and out inside each word so the light appears to
        // travel naturally instead of blinking at timing boundaries.
        return 0.68 + sin(progress * .pi) * 0.32
    }
}

private struct WordGlowRenderState {
    let base: AttributedString
    let glowMask: AttributedString
    let progress: Double
    let hasActiveWord: Bool
}
