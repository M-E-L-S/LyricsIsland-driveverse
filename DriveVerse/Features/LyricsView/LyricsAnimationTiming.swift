import Foundation

struct LyricPullTiming {
    let followDuration: Double
    let stagger: Double

    static let standard = LyricPullTiming(followDuration: 0.70)

    init(followDuration: Double) {
        self.followDuration = followDuration
        stagger = followDuration * 0.04
    }

    var settleDuration: Double { followDuration - 3 * stagger }
    var totalDuration: Double { settleDuration + 7 * stagger }

    func delay(lineIndex: Int, originIndex: Int) -> Double {
        Double(min(7, abs(lineIndex - originIndex))) * stagger
    }

    static func firstPlaybackTimeMs(for line: LyricsLine) -> Int {
        min(line.startTimeMs, line.words?.first?.startTimeMs ?? line.startTimeMs)
    }

    static func earliestAdvanceTimeMs(to index: Int, in lines: [LyricsLine]) -> Int? {
        guard index > 0 else { return nil }
        let previous = lines[index - 1]
        let lastWord = previous.words?.last {
            !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return max(firstPlaybackTimeMs(for: previous), lastWord?.startTimeMs ?? previous.startTimeMs)
    }

    private static func completionMarginMs(to index: Int, in lines: [LyricsLine]) -> Int {
        let firstPlayback = firstPlaybackTimeMs(for: lines[index])
        let earliest = earliestAdvanceTimeMs(to: index, in: lines) ?? firstPlayback - 1_500
        let window = max(0, firstPlayback - earliest)
        return min(window, max(20, min(40, Int(Double(window) * 0.08))))
    }

    func advanceStartTimeMs(to index: Int, in lines: [LyricsLine]) -> Int {
        let firstPlayback = Self.firstPlaybackTimeMs(for: lines[index])
        // The destination is three rows after the pull origin, so its delay
        // plus settling time is followDuration. Later rows may keep following.
        let trigger = firstPlayback - Int(ceil(followDuration * 1_000))
            - Self.completionMarginMs(to: index, in: lines)
        return max(trigger, Self.earliestAdvanceTimeMs(to: index, in: lines) ?? trigger)
    }

    func fittingBeforeFirstGlyph(remainingMs: Int) -> LyricPullTiming {
        let margin = min(20, max(0, remainingMs))
        let available = max(0, Double(remainingMs - margin) / 1_000)
        return LyricPullTiming(followDuration: min(followDuration, available))
    }

    static func forLine(_ index: Int, in lines: [LyricsLine]) -> LyricPullTiming {
        let nextIntervalMs = index + 1 < lines.count
            ? max(0, lines[index + 1].startTimeMs - lines[index].startTimeMs)
            : 1_500
        var duration = min(0.70, max(0.48, Double(nextIntervalMs) / 1_000 * 0.72))
        if let earliest = earliestAdvanceTimeMs(to: index, in: lines) {
            let windowMs = max(0, firstPlaybackTimeMs(for: lines[index]) - earliest
                - completionMarginMs(to: index, in: lines))
            // A short final word speeds up the same pull curve instead of
            // starting the advance while an earlier word is still playing.
            duration = min(duration, Double(windowMs) / 1_000)
        }
        return LyricPullTiming(followDuration: duration)
    }
}

struct TailLetterMotion {
    let lift: Double
    let glow: Double
    let illumination: Double

    static func state(progress: Double, letterIndex: Int?, letterCount: Int) -> TailLetterMotion {
        guard let letterIndex, letterCount > 0 else {
            return TailLetterMotion(lift: 0, glow: 0, illumination: 0)
        }
        let riseDuration = 0.24
        let holdDuration = 0.06
        let revealSpan = letterCount > 1 ? (1 - riseDuration) / 2 : 0
        let start = Double(letterIndex) / Double(max(1, letterCount - 1)) * revealSpan
        let elapsed = progress - start
        let rise = smootherStep(elapsed / riseDuration)
        // The first letter lands exactly when the final letter reaches its
        // peak. The same descent then reaches each remaining letter in turn.
        let fallDuration = letterCount > 1
            ? revealSpan - holdDuration
            : 1 - riseDuration - holdDuration
        let fall = min(1, max(0, (elapsed - riseDuration - holdDuration) / fallDuration))
        let glowFade = smoothStep((fall - 0.80) / 0.20)
        return TailLetterMotion(
            lift: 6.2 * rise * (1 - smoothStep(fall)),
            glow: 0.88 * rise * (1 - glowFade),
            illumination: rise
        )
    }

    private static func smoothStep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }

    private static func smootherStep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        // Zero velocity and acceleration at both ends make the slower lift
        // start and reach its peak without a sharp change in motion.
        return value * value * value * (value * (value * 6 - 15) + 10)
    }
}
