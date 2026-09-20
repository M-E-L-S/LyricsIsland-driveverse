import SwiftUI

/// Karaoke-style word highlighting driven locally from the playback anchor.
/// It doesn't require mutating the cached lyric or polling a provider.
struct WordTimedText: View {
    let line: LyricsLine
    let playback: NowPlayingState
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    var completedColor: Color = .primary
    var activeColor: Color = .accentColor
    var pendingColor: Color = .secondary.opacity(0.45)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !playback.isPlaying)) { timeline in
            Text(attributedText(at: timeline.date))
        }
    }

    private func attributedText(at date: Date) -> AttributedString {
        guard let words = line.words, !words.isEmpty else {
            return AttributedString(LyricsTextRenderer.primary(for: line, options: options))
        }
        let position = SyncEngine.extrapolatedPositionMs(anchor: playback, at: date) - timingOffsetMs
        var result = AttributedString()
        for word in words {
            var part = AttributedString(ChineseTextConverter.convert(
                word.original,
                using: options.chineseConversion
            ))
            if position >= word.endTimeMs {
                part.foregroundColor = completedColor
            } else if position >= word.startTimeMs {
                part.foregroundColor = activeColor
            } else {
                part.foregroundColor = pendingColor
            }
            result.append(part)
        }
        return result
    }
}
