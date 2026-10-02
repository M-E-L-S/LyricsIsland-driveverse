import Foundation
import Testing
@testable import DriveVerse

@Suite struct LyricsAnimationTimingTests {
    @Test func destinationRowSettlesBeforeTheFirstGlyphWhileLaterRowsMayKeepFollowing() {
        let lines = [0, 5_000, 5_120, 6_000, 8_000].map {
            LyricsLine(startTimeMs: $0, original: "line")
        }
        for index in 1..<lines.count {
            let timing = LyricPullTiming.forLine(index, in: lines)
            let trigger = timing.advanceStartTimeMs(to: index, in: lines)
            let destinationDuration = timing.delay(lineIndex: index, originIndex: index - 3)
                + timing.settleDuration
            let destinationFinish = Double(trigger) + destinationDuration * 1_000
            let laterRowFinish = Double(trigger) + timing.totalDuration * 1_000
            #expect(destinationFinish < Double(lines[index].startTimeMs))
            #expect(trigger >= lines[index - 1].startTimeMs)
            #expect(laterRowFinish > destinationFinish)
            if index == 1 {
                #expect(laterRowFinish > Double(lines[index].startTimeMs))
            }
        }
    }

    @Test func shortFinalWordSpeedsUpThePullWithoutAdvancingBeforeItStarts() {
        let lines = [
            LyricsLine(startTimeMs: 0, original: "a final word", words: [
                LyricWordTiming(startTimeMs: 0, endTimeMs: 4_750, original: "a final "),
                LyricWordTiming(startTimeMs: 4_750, endTimeMs: 5_000, original: "word"),
                LyricWordTiming(startTimeMs: 4_990, endTimeMs: 5_000, original: " ")
            ]),
            LyricsLine(startTimeMs: 5_000, original: "next"),
            LyricsLine(startTimeMs: 8_000, original: "later")
        ]
        let timing = LyricPullTiming.forLine(1, in: lines)
        let trigger = timing.advanceStartTimeMs(to: 1, in: lines)
        #expect(LyricPullTiming.earliestAdvanceTimeMs(to: 1, in: lines) == 4_750)
        #expect(trigger >= 4_750)
        #expect(timing.followDuration < LyricPullTiming.standard.followDuration)
        #expect(Double(trigger) + timing.followDuration * 1_000 < 5_000)
    }

    @Test func longFinalWordDoesNotStartThePullAtTheBeginningOfTheWord() {
        let lines = [
            LyricsLine(startTimeMs: 0, original: "held word", words: [
                LyricWordTiming(startTimeMs: 0, endTimeMs: 1_000, original: "held "),
                LyricWordTiming(startTimeMs: 1_000, endTimeMs: 5_000, original: "word")
            ]),
            LyricsLine(startTimeMs: 5_000, original: "next"),
            LyricsLine(startTimeMs: 8_000, original: "later")
        ]
        let timing = LyricPullTiming.forLine(1, in: lines)
        #expect(timing.advanceStartTimeMs(to: 1, in: lines) == 4_260)
    }

    @Test func lateWakeFitsOnlyTheDestinationRowIntoTheRemainingTime() {
        let timing = LyricPullTiming.standard.fittingBeforeFirstGlyph(remainingMs: 200)
        #expect(timing.followDuration < 0.2)
        #expect(timing.totalDuration > 0.2)
        #expect(LyricPullTiming.standard.fittingBeforeFirstGlyph(remainingMs: 0).followDuration == 0)
    }

    @Test func firstGlyphBeforeTheLineTimestampSetsTheAdvanceDeadline() {
        let line = LyricsLine(startTimeMs: 3_000, original: "early", words: [
            LyricWordTiming(startTimeMs: 2_900, endTimeMs: 4_200, original: "early")
        ])
        #expect(LyricPullTiming.firstPlaybackTimeMs(for: line) == 2_900)
    }

    @Test func firstLetterLandsAsTheFinalLetterReachesItsPeak() {
        for count in [2, 5, 24, 40, 100] {
            let first = TailLetterMotion.state(progress: 0.62, letterIndex: 0, letterCount: count)
            let last = TailLetterMotion.state(progress: 0.62, letterIndex: count - 1, letterCount: count)
            #expect(abs(first.lift) < 0.000001)
            #expect(abs(last.lift - 6.2) < 0.000001)
            #expect(last.illumination == 1)
            #expect(abs(last.glow - 0.88) < 0.000001)
            for index in 1..<count {
                let landing = 0.62 + Double(index) / Double(count - 1) * 0.38
                let letter = TailLetterMotion.state(progress: landing, letterIndex: index, letterCount: count)
                #expect(abs(letter.lift) < 0.000001)
            }
        }
    }

    @Test func lettersKeepTheirGlowDuringTheSlowDescent() {
        let peak = TailLetterMotion.state(progress: 0.27, letterIndex: 0, letterCount: 8)
        let falling = TailLetterMotion.state(progress: 0.44, letterIndex: 0, letterCount: 8)
        #expect(peak.lift > falling.lift)
        #expect(falling.lift > 0)
        #expect(falling.glow == peak.glow)
        #expect(falling.illumination == 1)
    }

    @Test func letterRiseIsSlowerAndStartsGently() {
        let early = TailLetterMotion.state(progress: 0.06, letterIndex: 0, letterCount: 8)
        let halfway = TailLetterMotion.state(progress: 0.12, letterIndex: 0, letterCount: 8)
        let peak = TailLetterMotion.state(progress: 0.24, letterIndex: 0, letterCount: 8)
        #expect(early.lift < 6.2 * 0.15)
        #expect(abs(halfway.lift - 3.1) < 0.000001)
        #expect(abs(peak.lift - 6.2) < 0.000001)
        #expect(early.lift < halfway.lift)
        #expect(halfway.lift < peak.lift)
    }

    @Test func singleLetterAndAllLongWordLettersFinishAtBaseline() {
        for count in [1, 3, 30, 100] {
            for index in 0..<count {
                let initial = TailLetterMotion.state(progress: 0, letterIndex: index, letterCount: count)
                let completed = TailLetterMotion.state(progress: 1, letterIndex: index, letterCount: count)
                #expect(initial.lift == 0)
                #expect(abs(completed.lift) < 0.000001)
                #expect(abs(completed.glow) < 0.000001)
                #expect(completed.illumination == 1)
            }
        }
    }

#if canImport(UIKit)
    @Test func letterLayoutAcceptsShortAndLongWordsAndKeepsWrappedLetters() throws {
        for word in ["I", "Hi", "supercalifragilisticexpialidocious"] {
            let layout = try #require(TailLetterLayout.make(text: word, fontSize: 32))
            #expect(layout.letterCount == word.count)
            #expect(layout.slices.count == word.count)
        }
        let word = "supercalifragilisticexpialidocious"
        let layout = try #require(TailLetterLayout.make(text: word, fontSize: 32))
        let wrapped = try #require(layout.fitting(width: 120))
        #expect(wrapped.slices.count == word.count)
        #expect(wrapped.slices.contains { $0.top > 0 })
        #expect(wrapped.width == 120)
    }
#endif
}
