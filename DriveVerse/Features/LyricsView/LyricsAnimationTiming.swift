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

    func advanceStartTimeMs(to index: Int, in lines: [LyricsLine]) -> Int {
        let firstPlayback = Self.firstPlaybackTimeMs(for: lines[index])
        let interval = index > 0
            ? max(0, firstPlayback - Self.firstPlaybackTimeMs(for: lines[index - 1]))
            : 1_500
        // Include every row's stagger and a small scheduling margin so the
        // whole pull finishes before the next line begins to fill.
        let margin = min(60, Int(Double(interval) * 0.08))
        return firstPlayback - Int(ceil(totalDuration * 1_000)) - margin
    }

    static func forLine(_ index: Int, in lines: [LyricsLine]) -> LyricPullTiming {
        let nextIntervalMs = index + 1 < lines.count
            ? max(0, lines[index + 1].startTimeMs - lines[index].startTimeMs)
            : 1_500
        var duration = min(0.70, max(0.48, Double(nextIntervalMs) / 1_000 * 0.72))
        if index > 0 {
            let entryInterval = max(1, firstPlaybackTimeMs(for: lines[index])
                - firstPlaybackTimeMs(for: lines[index - 1]))
            // Very short lines keep the same curve and stagger proportions,
            // compressed enough that successive advances cannot overlap.
            duration = min(duration, Double(entryInterval) / 1_000 * 0.72 / 1.16)
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
        let riseDuration = 0.12
        let holdDuration = 0.06
        let revealSpan = letterCount > 1 ? 0.44 : 0
        let start = Double(letterIndex) / Double(max(1, letterCount - 1)) * revealSpan
        let elapsed = progress - start
        let rise = smoothStep(elapsed / riseDuration)
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
}
