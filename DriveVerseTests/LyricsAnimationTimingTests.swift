import Foundation
import Testing
@testable import DriveVerse

@Suite struct LyricsAnimationTimingTests {
    @Test func everyStaggeredRowSettlesBeforeTheNextFirstGlyph() {
        let lines = [0, 5_000, 5_120, 6_000, 8_000].map {
            LyricsLine(startTimeMs: $0, original: "line")
        }
        for index in 1..<lines.count {
            let timing = LyricPullTiming.forLine(index, in: lines)
            let trigger = timing.advanceStartTimeMs(to: index, in: lines)
            let latestFinish = Double(trigger) + timing.totalDuration * 1_000
            #expect(latestFinish < Double(lines[index].startTimeMs))
            #expect(trigger > lines[index - 1].startTimeMs)
            #expect(timing.delay(lineIndex: index, originIndex: index - 3)
                + timing.settleDuration <= timing.totalDuration)
        }
    }

    @Test func firstGlyphBeforeTheLineTimestampSetsTheAdvanceDeadline() {
        let line = LyricsLine(startTimeMs: 3_000, original: "early", words: [
            LyricWordTiming(startTimeMs: 2_900, endTimeMs: 4_200, original: "early")
        ])
        #expect(LyricPullTiming.firstPlaybackTimeMs(for: line) == 2_900)
    }

    @Test func firstLetterLandsAsTheFinalLetterReachesItsPeak() {
        for count in [2, 5, 24, 40, 100] {
            let first = TailLetterMotion.state(progress: 0.56, letterIndex: 0, letterCount: count)
            let last = TailLetterMotion.state(progress: 0.56, letterIndex: count - 1, letterCount: count)
            #expect(abs(first.lift) < 0.000001)
            #expect(abs(last.lift - 6.2) < 0.000001)
            #expect(last.illumination == 1)
            #expect(abs(last.glow - 0.88) < 0.000001)
            for index in 1..<count {
                let landing = 0.56 + Double(index) / Double(count - 1) * 0.44
                let letter = TailLetterMotion.state(progress: landing, letterIndex: index, letterCount: count)
                #expect(abs(letter.lift) < 0.000001)
            }
        }
    }

    @Test func lettersKeepTheirGlowDuringTheSlowDescent() {
        let peak = TailLetterMotion.state(progress: 0.15, letterIndex: 0, letterCount: 8)
        let falling = TailLetterMotion.state(progress: 0.35, letterIndex: 0, letterCount: 8)
        #expect(peak.lift > falling.lift)
        #expect(falling.lift > 0)
        #expect(falling.glow == peak.glow)
        #expect(falling.illumination == 1)
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
