import Testing
@testable import DriveVerse

@Suite struct LiveLyricsFillTimelineTests {
    private func word(_ text: String, _ start: Int, _ end: Int) -> LyricWordTiming {
        LyricWordTiming(startTimeMs: start, endTimeMs: end, original: text)
    }

    @Test func handsOffBeforeThePreviousWordFinishes() {
        let words = [word("你", 0, 1_200), word("好", 1_200, 2_400)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 0, after: 0)
                == .animate(target: 1, durationMs: 1_200))
        // Already target the next word while the old animation is in flight.
        #expect(LiveLyricsFillTimeline.next(words: words, at: 1_080, after: 1)
                == .animate(target: 2, durationMs: 1_320))
    }

    @Test func rapidSyllablesShareAnAnimationInsteadOfWaitingForTicks() {
        let words = (0..<30).map { word("字", $0 * 100, ($0 + 1) * 100) }
        #expect(LiveLyricsFillTimeline.next(words: words, at: 0, after: 0)
                == .animate(target: 12, durationMs: 1_200))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 1_080, after: 12)
                == .animate(target: 23, durationMs: 1_220))
    }

    @Test func longWordContinuesWithinTheSystemAnimationLimit() {
        let words = [word("long", 0, 5_000)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 0, after: 0)
                == .animate(target: 1.44, durationMs: 1_800))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 1_680, after: 1.44)
                == .animate(target: 2.784, durationMs: 1_800))
    }

    @Test func singingGapDoesNotLightUpTheNextWordEarly() {
        let words = [word("你", 0, 200), word("好", 800, 1_400)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 0, after: 0)
                == .animate(target: 1, durationMs: 200))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 200, after: 1)
                == .wait(milliseconds: 600))
        #expect(LiveLyricsFillTimeline.progress(words: words, at: 500) == 1)
        #expect(LiveLyricsFillTimeline.next(words: words, at: 800, after: 1)
                == .animate(target: 2, durationMs: 600))
    }

    @Test func completedTargetIsNotResetOrResent() {
        let words = [word("你", 0, 600)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 480, after: 1)
                == .wait(milliseconds: 120))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 600, after: 1) == nil)
        #expect(LiveLyricsFillTimeline.next(words: [], at: 0, after: 0) == nil)
    }

    @Test func seekAndGraphemesUseTheCurrentPosition() {
        let words = [word("👨‍👩‍👧‍👦", 1_000, 2_000), word("e\u{301}", 2_000, 3_000)]
        #expect(LiveLyricsFillTimeline.progress(words: words, at: 500) == 0)
        #expect(LiveLyricsFillTimeline.progress(words: words, at: 1_500) == 0.5)
        #expect(LiveLyricsFillTimeline.progress(words: words, at: 2_500) == 1.5)
        #expect(LiveLyricsFillTimeline.next(words: words, at: 2_500, after: 1.5)
                == .animate(target: 2, durationMs: 500))
    }

    @Test func naturalLineChangeStartsEmptyEvenWhenDeliveryIsLate() {
        let words = (0..<10).map { word("字", $0 * 100, ($0 + 1) * 100) }
        let initial = LiveLyricsFillTimeline.initialTarget(
            words: words, at: 180, restartingLine: true
        )
        #expect(initial == 0)
        // After the new text has appeared, animate from that empty endpoint
        // through the missed prefix and catch up before the line finishes.
        #expect(LiveLyricsFillTimeline.next(words: words, at: 680, after: initial)
                == .animate(target: 10, durationMs: 320))
    }

    @Test func seekAndResumeDoNotReplayTheBeginning() {
        let words = (0..<10).map { word("字", $0 * 100, ($0 + 1) * 100) }
        #expect(LiveLyricsFillTimeline.initialTarget(
            words: words, at: 650, restartingLine: false
        ) == 6.5)
    }

    @Test func delayedStartStillRevealsAShortCompletedLine() {
        let words = [word("你好", 0, 200)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 500, after: 0)
                == .animate(target: 2, durationMs: 450))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 830, after: 2) == nil)
    }

    @Test func delayedStartCatchesUpOnlyThePrefixBeforeASingingGap() {
        let words = [word("你", 0, 200), word("好", 800, 1_400)]
        #expect(LiveLyricsFillTimeline.next(words: words, at: 500, after: 0)
                == .animate(target: 1, durationMs: 300))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 680, after: 1)
                == .wait(milliseconds: 120))
    }

    @Test func continuousFastLyricsUseFewerThanOneEndpointPerSecond() {
        let words = (0..<100).map { word("字", $0 * 100, ($0 + 1) * 100) }
        var position = 0
        var target = 0.0
        var endpointCount = 0
        for _ in 0..<30 {
            guard let step = LiveLyricsFillTimeline.next(words: words, at: position, after: target)
            else { break }
            switch step {
            case .wait(let milliseconds): position += milliseconds
            case .animate(let value, let milliseconds):
                endpointCount += 1
                #expect(value > target)
                #expect(milliseconds <= 2_000)
                target = value
                position += max(1, milliseconds - LiveLyricsFillTimeline.handoffLeadMs)
            }
        }
        #expect(target == 100)
        #expect(endpointCount <= 10)
    }

    @Test func heldTailCannotFillEarlyWhenItsLetterDensityDiffersFromThePrefix() {
        let words = [word("I ", 0, 800), word("wonderful", 800, 3_200)]
        // A combined linear phase used to cross the tail's first character
        // around 626 ms, before the token actually started at 800 ms.
        #expect(LiveLyricsFillTimeline.next(words: words, at: 0, after: 0, heldTailStartMs: 800)
            == .animate(target: 2, durationMs: 800))
        #expect(LiveLyricsFillTimeline.next(words: words, at: 680, after: 2, heldTailStartMs: 800)
            == .wait(milliseconds: 120))
        guard case .animate(let target, let duration)? = LiveLyricsFillTimeline.next(
            words: words, at: 800, after: 2, heldTailStartMs: 800
        ) else { Issue.record("Tail did not begin filling at its singing boundary"); return }
        #expect(target > 2 && duration <= 2_000)
    }
}
