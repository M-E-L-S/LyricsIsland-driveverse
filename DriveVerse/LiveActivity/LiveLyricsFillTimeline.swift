/// Plans native animation endpoints from lyric time rather than sync ticks.
/// Short adjacent words share a phase; singing pauses remain real pauses.
enum LiveLyricsFillTimeline {
    static let maximumPhaseMs = 1_800
    static let minimumPhaseMs = 450
    static let handoffLeadMs = 120

    enum Step: Equatable {
        case wait(milliseconds: Int)
        case animate(target: Double, durationMs: Int)
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
                     after previousTarget: Double) -> Step? {
        guard let index = words.firstIndex(where: { $0.endTimeMs > positionMs }) else {
            return nil
        }
        if words[index].startTimeMs > positionMs {
            return .wait(milliseconds: words[index].startTimeMs - positionMs)
        }
        let limit = positionMs + maximumPhaseMs
        var end = min(limit, words[index].endTimeMs)
        var nextIndex = index + 1
        // Combine rapid syllables so delivery latency doesn't create a stop
        // between every glyph. Do not combine across a singing pause.
        while end - positionMs < minimumPhaseMs, nextIndex < words.count,
              words[nextIndex].startTimeMs <= end {
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
