/// Plans native animation endpoints from lyric time rather than sync ticks.
/// Short adjacent words share a phase; singing pauses remain real pauses.
enum LiveLyricsFillTimeline {
    static let maximumPhaseMs = 1_800
    static let minimumPhaseMs = 1_200
    static let handoffLeadMs = 120

    enum Step: Equatable {
        case wait(milliseconds: Int)
        case animate(target: Double, durationMs: Int)
    }

    static func initialTarget(words: [LyricWordTiming], at positionMs: Int,
                              restartingLine: Bool) -> Double {
        // Natural line changes must archive an empty mask first. Seeks, session
        // starts and pause/resume keep their actual playback progress instead.
        restartingLine ? 0 : progress(words: words, at: positionMs)
    }

    static func progress(words: [LyricWordTiming], at positionMs: Int) -> Double {
        var completed = 0.0
        for word in words {
            if positionMs < word.startTimeMs { return completed }
            let count = Double(word.original.count)
            if positionMs < word.endTimeMs {
                return completed + count * Double(positionMs - word.startTimeMs)
                    / Double(max(1, word.endTimeMs - word.startTimeMs))
            }
            completed += count
        }
        return completed
    }

    static func next(words: [LyricWordTiming], at positionMs: Int,
                     after previousTarget: Double, heldTailStartMs: Int? = nil) -> Step? {
        guard let index = words.firstIndex(where: { $0.endTimeMs > positionMs }) else {
            // A short line may finish singing while its text is transitioning.
            // Reveal the missed prefix smoothly instead of leaving it blank.
            let target = progress(words: words, at: positionMs)
            if target > previousTarget {
                return .animate(target: target, durationMs: 450)
            }
            return nil
        }
        if words[index].startTimeMs > positionMs {
            let gapMs = words[index].startTimeMs - positionMs
            let target = progress(words: words, at: positionMs)
            if target > previousTarget {
                // Catch up a prefix missed during the line transition, but do
                // not reveal any part of the word after this singing pause.
                return .animate(target: target, durationMs: min(450, gapMs))
            }
            return .wait(milliseconds: gapMs)
        }
        let limit = positionMs + maximumPhaseMs
        var end = min(limit, words[index].endTimeMs)
        if let heldTailStartMs, positionMs < heldTailStartMs {
            end = min(end, heldTailStartMs)
        }
        var nextIndex = index + 1
        // Combine rapid syllables so delivery latency doesn't create a stop
        // between every glyph. Keep singing pauses and a held tail's start as
        // hard boundaries: a linear phase must not light that token early.
        while end - positionMs < minimumPhaseMs, nextIndex < words.count,
              words[nextIndex].startTimeMs <= end,
              words[nextIndex].startTimeMs != heldTailStartMs {
            end = min(limit, words[nextIndex].endTimeMs)
            nextIndex += 1
        }
        let target = progress(words: words, at: end)
        if target > previousTarget {
            return .animate(target: target, durationMs: end - positionMs)
        }
        // The last endpoint is already in flight. Wait until it is reached
        // instead of repeatedly submitting the same target or resetting it.
        return .wait(milliseconds: max(1, end - positionMs))
    }
}
