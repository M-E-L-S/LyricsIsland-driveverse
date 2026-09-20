import Foundation
import SwiftUI

/// Apple Music-style word timing: each glyph is gradually filled from its
/// leading edge instead of switching the entire word on at once. Completed
/// text also settles a fraction upward, giving the sung phrase a restrained
/// sense of motion without a conspicuous glow.
struct WordTimedText: View {
    let line: LyricsLine
    let playback: NowPlayingState
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    var completedColor: Color = .primary
    var activeColor: Color = .primary
    var pendingColor: Color = .secondary.opacity(0.45)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playback.isPlaying)) { timeline in
            if let words = line.words, !words.isEmpty {
                let position = SyncEngine.extrapolatedPositionMs(
                    anchor: playback,
                    at: timeline.date
                ) - timingOffsetMs

                LyricsWordFlowLayout {
                    ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                        ProgressiveWordFill(
                            text: ChineseTextConverter.convert(
                                word.original,
                                using: options.chineseConversion
                            ),
                            fraction: fillFraction(for: word, at: position),
                            completedColor: completedColor,
                            activeColor: activeColor,
                            pendingColor: pendingColor
                        )
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: LyricsTextRenderer.primary(for: line, options: options)))
            } else {
                Text(LyricsTextRenderer.primary(for: line, options: options))
            }
        }
    }

    private func fillFraction(for word: LyricWordTiming, at position: Int) -> Double {
        if position <= word.startTimeMs { return 0 }
        if position >= word.endTimeMs { return 1 }
        let duration = max(1, word.endTimeMs - word.startTimeMs)
        return min(1, max(0, Double(position - word.startTimeMs) / Double(duration)))
    }
}

private struct ProgressiveWordFill: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let text: String
    let fraction: Double
    let completedColor: Color
    let activeColor: Color
    let pendingColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .foregroundStyle(pendingColor)

            Text(text)
                .foregroundStyle(fraction >= 1 ? completedColor : activeColor)
                .mask {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            if layoutDirection == .rightToLeft {
                                Spacer(minLength: 0)
                            }
                            Rectangle()
                                .frame(width: geometry.size.width * fraction)
                                .blur(radius: 0.7)
                            if layoutDirection != .rightToLeft {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
        }
        // Apple Music's completed words lift only subtly. Driving this from
        // the same fraction keeps the movement continuous within every glyph.
        .offset(y: -1.35 * fraction)
    }
}

/// Places provider word tokens with zero synthetic spacing and wraps them as
/// one lyric line. Each token remains an independent mask, which lets a single
/// Chinese character or Latin word fill continuously without losing native
/// SwiftUI text shaping.
private struct LyricsWordFlowLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        measurements(for: subviews, width: proposal.width).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = measurements(for: subviews, width: bounds.width)
        for (index, position) in result.positions.enumerated() {
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func measurements(
        for subviews: Subviews,
        width proposedWidth: CGFloat?
    ) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let maximumWidth = max(1, proposedWidth ?? .greatestFiniteMagnitude)
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maximumWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil))
            }
            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += lineHeight
                lineHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width
            lineHeight = max(lineHeight, size.height)
            measuredWidth = max(measuredWidth, x)
        }

        return (
            CGSize(width: min(maximumWidth, measuredWidth), height: y + lineHeight),
            positions,
            sizes
        )
    }
}
