import Foundation

struct TailLetterMotion {
    let lift: Double
    let glow: Double
    let illumination: Double

    static func state(progress: Double, letterIndex: Int?, letterCount: Int) -> TailLetterMotion {
        guard let letterIndex, letterCount > 0 else {
            return TailLetterMotion(lift: 0, glow: 0, illumination: 0)
        }
        let riseDuration = 0.48
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

/// Metadata for the same held final token enhanced by the full-screen view.
struct LiveLyricsTailWord: Codable, Hashable {
    let characterStart: Int
    let startMs: Int
    let endMs: Int

    static func make(characterStart: Int, startMs: Int, endMs: Int) -> Self? {
        guard characterStart >= 0, endMs - startMs >= 1_200 else { return nil }
        return Self(characterStart: characterStart, startMs: startMs, endMs: endMs)
    }

    func progress(at positionMs: Int) -> Double {
        let fraction = Double(positionMs - startMs) / Double(max(1, endMs - startMs))
        return min(1, max(0, (fraction - 0.12) / 0.88))
    }

    func position(at progress: Double) -> Int {
        startMs + Int((Double(endMs - startMs) * (0.12 + 0.88 * progress)).rounded())
    }
}

/// Archive endpoints for native offset, opacity and shadow interpolation.
/// This runs only during a held final token, never as a widget-local timer.
enum LiveLyricsTailAnimation {
    enum Step: Equatable {
        case wait(milliseconds: Int)
        case animate(progress: Double, durationMs: Int)
    }

    static func next(word: LiveLyricsTailWord, at positionMs: Int,
                     after previousTarget: Double) -> Step? {
        let onset = word.position(at: 0)
        if positionMs < onset { return .wait(milliseconds: onset - positionMs) }
        if positionMs >= word.endMs {
            return previousTarget < 1 ? .animate(progress: 1, durationMs: 180) : nil
        }
        let current = word.progress(at: positionMs)
        if previousTarget >= 1 { return nil }
        var end = word.endMs
        // Peak/hold/descent landmarks from TailLetterMotion. Combine very
        // short phases to keep the archived view tree's update rate bounded.
        for landmark in [0.48, 0.74, 1.0] {
            let candidate = word.position(at: landmark)
            if landmark > max(current, previousTarget), candidate - positionMs >= 180 {
                end = candidate
                break
            }
        }
        end = min(end, positionMs + 1_800)
        let target = word.progress(at: end)
        if target <= previousTarget {
            return .wait(milliseconds: max(1, word.position(at: previousTarget) - positionMs))
        }
        return .animate(progress: target, durationMs: max(1, end - positionMs))
    }

    static func wholeWordMotion(progress: Double) -> TailLetterMotion {
        let progress = min(1, max(0, progress))
        let wave = max(0, sin(progress * .pi))
        return TailLetterMotion(lift: 6.2 * pow(wave, 1.3),
                                glow: 0.88 * pow(wave, 1.2), illumination: 0)
    }
}
