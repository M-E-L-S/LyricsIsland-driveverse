import Foundation
import SwiftUI
#if canImport(UIKit)
import CoreText
import UIKit
#endif

/// Apple Music-style word timing: each glyph is gradually filled from its
/// leading edge instead of switching the entire word on at once. Completed
/// text rises on a slower curve, while a held final token briefly lifts and
/// glows before settling to the same height as its neighbors.
struct WordTimedText: View {
    let line: LyricsLine
    let playback: NowPlayingState
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    let fontSize: CGFloat
    var completedColor: Color = .primary
    var activeColor: Color = .primary
    var pendingColor: Color = .secondary.opacity(0.45)

    var body: some View {
        if let words = line.words, !words.isEmpty {
            // Conversion is stable for the entire line; keep it out of the
            // clock-driven view update.
            let renderedWords = words.map {
                ChineseTextConverter.convert($0.original, using: options.chineseConversion)
            }
            let finalLetterLayout: TailLetterLayout? = {
                guard let lastWord = words.last,
                      lastWord.endTimeMs - lastWord.startTimeMs >= 1_200,
                      let renderedLastWord = renderedWords.last else { return nil }
                return TailLetterLayout.make(text: renderedLastWord, fontSize: fontSize)
            }()
            let accessibilityText = LyricsTextRenderer.primary(for: line, options: options)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                    paused: !playback.isPlaying)) { timeline in
                let position = SyncEngine.extrapolatedPositionMs(
                    anchor: playback,
                    at: timeline.date
                ) - timingOffsetMs

                let states = words.map { fillState(for: $0, at: position) }
                LyricsWordFlowLayout {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        let lift = min(1, max(0, Double(position - word.startTimeMs)
                            / Double(max(750, word.endTimeMs - word.startTimeMs))))
                        let preview = previewIntensity(for: index, states: states)
                        Group {
                            if states[index].fraction >= 1 && lift >= 1 {
                                Text(renderedWords[index])
                                    .foregroundStyle(completedColor)
                                    .offset(y: -2.2)
                            } else if states[index].fraction == 0 && preview == 0 {
                                Text(renderedWords[index])
                                    .foregroundStyle(pendingColor)
                            } else {
                                ProgressiveWordFill(
                                    text: renderedWords[index],
                                    fraction: states[index].fraction,
                                    liftProgress: lift,
                                    isActive: states[index].isActive,
                                    previewIntensity: preview,
                                    isLastWord: index == words.count - 1,
                                    durationMs: max(0, word.endTimeMs - word.startTimeMs),
                                    tailLetterLayout: index == words.count - 1 ? finalLetterLayout : nil,
                                    completedColor: completedColor,
                                    activeColor: activeColor,
                                    pendingColor: pendingColor
                                )
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityText))
            }
        } else {
            Text(LyricsTextRenderer.primary(for: line, options: options))
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

/// Uses the same token layout as the timed line without running a display clock.
/// This keeps spaces, wrapping, and line height stable when playback reaches it.
struct StaticWordTimedText: View {
    let line: LyricsLine
    let options: LyricsDisplayOptions

    var body: some View {
        if let words = line.words, !words.isEmpty {
            LyricsWordFlowLayout {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    Text(ChineseTextConverter.convert(
                        word.original,
                        using: options.chineseConversion
                    ))
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
    let tailLetterLayout: TailLetterLayout?
    let completedColor: Color
    let activeColor: Color
    let pendingColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .foregroundStyle(pendingColor)

            if fraction > 0 || isActive {
                if isLongTail, let tailLetterLayout {
                    letterTailFill(tailLetterLayout)
                        .opacity(fillOnsetOpacity)
                } else {
                    Text(text)
                        .foregroundStyle(fraction >= 1 ? completedColor : activeColor)
                        .mask { fillMask }
                        .opacity(fillOnsetOpacity)
                }
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

            if isLongTail, isActive, tailLetterLayout == nil {
                Text(text)
                    .foregroundStyle(Color.white.opacity(tailGlow * 0.72))
                    .mask { fillMask }
                    .blur(radius: 7)

                Text(text)
                    .foregroundStyle(Color.white.opacity(tailGlow * 0.32))
                    .mask { fillMask }
            }
        }
        .offset(y: -(2.2 * easedLift + (tailLetterLayout == nil ? tailLift : 0)))
    }

    private func letterTailFill(_ layout: TailLetterLayout) -> some View {
        // Each slice draws the same shaped word; masks isolate letters without
        // changing the token's width or kerning when the tail animation starts.
        ZStack(alignment: .leading) {
            ForEach(layout.slices) { slice in
                let glow = letterGlow(for: slice, count: layout.letterCount)
                Text(text)
                    .foregroundStyle(fraction >= 1 ? completedColor : activeColor)
                    .mask { fillMask }
                    .mask { letterMask(for: slice, layout: layout) }
                    .offset(y: -letterLift(for: slice, count: layout.letterCount))
                    .shadow(color: .white.opacity(glow * 0.72), radius: 7)
                    .shadow(color: .white.opacity(glow * 0.32), radius: 0)
            }
        }
    }

    private func letterMask(for slice: TailLetterSlice, layout: TailLetterLayout) -> some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / max(1, layout.width)
            Rectangle()
                .frame(width: max(1, (slice.end - slice.start) * scale + 1),
                       height: geometry.size.height)
                .position(x: (slice.start + slice.end) * scale / 2,
                          y: geometry.size.height / 2)
        }
    }

    private func letterLift(for slice: TailLetterSlice, count: Int) -> Double {
        6.2 * pow(sin(letterPhase(for: slice, count: count) * .pi), 1.3)
    }

    private func letterGlow(for slice: TailLetterSlice, count: Int) -> Double {
        pow(sin(letterPhase(for: slice, count: count) * .pi), 1.2) * 0.88
    }

    private func letterPhase(for slice: TailLetterSlice, count: Int) -> Double {
        guard let letterIndex = slice.letterIndex else { return 0 }
        let start = Double(letterIndex) / Double(max(1, count - 1)) * 0.65
        return min(1, max(0, (tailProgress - start) / 0.35))
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

private struct TailLetterSlice: Identifiable {
    let id: Int
    let start: CGFloat
    let end: CGFloat
    let letterIndex: Int?
}

private struct TailLetterLayout {
    let width: CGFloat
    let slices: [TailLetterSlice]
    let letterCount: Int

    static func make(text: String, fontSize: CGFloat) -> TailLetterLayout? {
#if canImport(UIKit)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.allSatisfy(\.isASCII),
              !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.letters.contains(scalar)
                      || CharacterSet.punctuationCharacters.contains(scalar)
              }) else { return nil }

        let letterCount = trimmed.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }.count
        guard (5...24).contains(letterCount) else { return nil }

        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = max(
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
            CTLineGetOffsetForStringIndex(line, text.utf16.count, nil)
        )
        guard width > 0 else { return nil }

        var slices: [TailLetterSlice] = []
        var utf16Index = 0
        var nextLetterIndex = 0
        for (index, character) in text.enumerated() {
            let characterText = String(character)
            let nextUTF16Index = utf16Index + characterText.utf16.count
            let start = CTLineGetOffsetForStringIndex(line, utf16Index, nil)
            let end = CTLineGetOffsetForStringIndex(line, nextUTF16Index, nil)
            let isLetter = characterText.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0)
            }
            slices.append(TailLetterSlice(
                id: index,
                start: min(start, end),
                end: max(start, end),
                letterIndex: isLetter ? nextLetterIndex : nil
            ))
            if isLetter { nextLetterIndex += 1 }
            utf16Index = nextUTF16Index
        }
        return TailLetterLayout(width: width, slices: slices, letterCount: letterCount)
#else
        return nil
#endif
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
