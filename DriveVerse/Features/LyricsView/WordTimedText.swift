import Foundation
import SwiftUI

/// Apple Music-style word timing: each glyph is gradually filled from its
/// leading edge instead of switching the entire word on at once. Completed
/// text rises on a slower curve, while a held final token briefly lifts and
/// glows before settling to the same height as its neighbors.
struct WordTimedText: View {
    let line: LyricsLine
    let playback: NowPlayingState
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    var completedColor: Color = .primary
    var activeColor: Color = .primary
    var pendingColor: Color = .secondary.opacity(0.45)

    var body: some View {
        // Let SwiftUI follow the display's native animation cadence (including
        // ProMotion) instead of imposing a second, lower-frequency clock.
        TimelineView(.animation(paused: !playback.isPlaying)) { timeline in
            if let words = line.words, !words.isEmpty {
                let position = SyncEngine.extrapolatedPositionMs(
                    anchor: playback,
                    at: timeline.date
                ) - timingOffsetMs

                let states = words.map { fillState(for: $0, at: position) }
                LyricsWordFlowLayout {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        ProgressiveWordFill(
                            text: ChineseTextConverter.convert(
                                word.original,
                                using: options.chineseConversion
                            ),
                            fraction: states[index].fraction,
                            liftProgress: min(1, max(0, Double(position - word.startTimeMs)
                                / Double(max(750, word.endTimeMs - word.startTimeMs)))),
                            isActive: states[index].isActive,
                            previewIntensity: previewIntensity(
                                for: index,
                                states: states
                            ),
                            isLastWord: index == words.count - 1,
                            durationMs: max(0, word.endTimeMs - word.startTimeMs),
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

    private func fillState(for word: LyricWordTiming, at position: Int) -> WordFillState {
        if position < word.startTimeMs {
            return WordFillState(fraction: 0, isActive: false)
        }
        if position >= word.endTimeMs {
            return WordFillState(fraction: 1, isActive: false)
        }
        let duration = max(1, word.endTimeMs - word.startTimeMs)
        return WordFillState(
            fraction: min(1, max(0, Double(position - word.startTimeMs) / Double(duration))),
            isActive: true
        )
    }

    private func previewIntensity(
        for index: Int,
        states: [WordFillState]
    ) -> Double {
        guard index > 0, states[index].fraction < 1 else { return 0 }
        let progress = states[index - 1].fraction
        let arrival = min(1, max(0, (progress - 0.76) / 0.24))
        // Keep the preview under the real fill until the whole word is bright.
        // Removing it at the first active frame made the remaining glyph dim.
        return smoothStep(arrival) * 0.20
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

private struct WordFillState {
    let fraction: Double
    let isActive: Bool
}

private struct ProgressiveWordFill: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let text: String
    let fraction: Double
    let liftProgress: Double
    let isActive: Bool
    let previewIntensity: Double
    let isLastWord: Bool
    let durationMs: Int
    let completedColor: Color
    let activeColor: Color
    let pendingColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .foregroundStyle(pendingColor)

            if fraction > 0 || isActive {
                Text(text)
                    .foregroundStyle(fraction >= 1 ? completedColor : activeColor)
                    .mask { fillMask }
                    .opacity(fillOnsetOpacity)
            }

            if previewIntensity > 0 {
                Text(text)
                    .foregroundStyle(activeColor.opacity(previewIntensity))
                    .mask {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [.white, .white.opacity(0.30), .clear],
                                startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                                endPoint: layoutDirection == .rightToLeft ? .leading : .trailing
                            )
                            .frame(width: min(28, geometry.size.width * 0.58))
                            .frame(maxWidth: .infinity,
                                   alignment: layoutDirection == .rightToLeft ? .trailing : .leading)
                        }
                    }
            }

            if isLongTail, isActive {
                Text(text)
                    .foregroundStyle(Color.white.opacity(tailGlow * 0.72))
                    .mask { fillMask }
                    .blur(radius: 7)

                Text(text)
                    .foregroundStyle(Color.white.opacity(tailGlow * 0.32))
                    .mask { fillMask }
            }
        }
        .offset(y: -(2.2 * easedLift + tailLift))
    }

    @ViewBuilder
    private var fillMask: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let edge = width * fraction
            let feather = min(18, max(8, width * 0.34))
            ZStack(alignment: layoutDirection == .rightToLeft ? .trailing : .leading) {
                Rectangle()
                    .frame(width: edge)
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.72), location: 0.28),
                        .init(color: .white.opacity(0.25), location: 0.66),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                    endPoint: layoutDirection == .rightToLeft ? .leading : .trailing
                )
                .frame(width: feather)
                .offset(x: layoutDirection == .rightToLeft
                    ? -(edge - feather * 0.12)
                    : edge - feather * 0.12)
            }
            .frame(width: width, height: geometry.size.height,
                   alignment: layoutDirection == .rightToLeft ? .trailing : .leading)
            .clipped()
        }
    }

    private var easedLift: Double {
        let progress = min(1, max(0, (liftProgress - 0.06) / 0.94))
        let remaining = 1 - progress
        // Cubic Bézier with a gentle start and finish, driven by the word clock.
        return 3 * remaining * remaining * progress * 0.08
            + 3 * remaining * progress * progress * 0.90
            + progress * progress * progress
    }

    private var fillOnsetOpacity: Double {
        let progress = min(1, max(0, fraction / 0.22))
        return progress * progress * (3 - 2 * progress)
    }

    private var isLongTail: Bool {
        isLastWord && durationMs >= 1_200
    }

    private var tailProgress: Double {
        guard isLongTail else { return 0 }
        return min(1, max(0, (fraction - 0.12) / 0.88))
    }

    private var tailLift: Double {
        6.2 * pow(sin(tailProgress * .pi), 1.3)
    }

    private var tailGlow: Double {
        pow(sin(tailProgress * .pi), 1.2) * 0.88
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
