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
            let destinationDuration = timing.delay(lineIndex: index, originIndex: index - 1)
                + timing.settleDuration
            let destinationFinish = Double(trigger) + destinationDuration * 1_000
            let laterRowFinish = Double(trigger) + timing.totalDuration * 1_000
            #expect(destinationFinish < Double(lines[index].startTimeMs))
            #expect(timing.followDuration >= LyricPullTiming.minimumFollowDuration)
            #expect(laterRowFinish > destinationFinish)
            let followingFinish = Double(trigger) + (
                timing.delay(lineIndex: index + 1, originIndex: index - 1)
                    + timing.settleDuration(lineIndex: index + 1, originIndex: index - 1)
            ) * 1_000
            #expect(followingFinish > Double(lines[index].startTimeMs))
        }
    }

    @Test func shortFinalWordAllowsEarlierAdvanceToPreserveMinimumDuration() {
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
        #expect(LyricPullTiming.earliestAdvanceTimeMs(to: 1, in: lines) == 4_530)
        #expect(trigger < 4_875)
        #expect(abs(timing.followDuration - LyricPullTiming.minimumFollowDuration) < 0.000001)
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

    @Test func lateWakeAndResumeKeepThePullFromExceedingTheSpeedLimit() {
        let timing = LyricPullTiming.standard.fittingBeforeFirstGlyph(remainingMs: 200)
        #expect(timing.followDuration == LyricPullTiming.minimumFollowDuration)
        #expect(timing.totalDuration > 0.2)
        #expect(timing.settleDuration(lineIndex: 2, originIndex: 0) >= 0.45)
        #expect(LyricPullTiming.standard.fittingBeforeFirstGlyph(remainingMs: 0).followDuration
            == LyricPullTiming.minimumFollowDuration)
    }

    @Test func sufficientTailWordWindowKeepsTheMidpointAsTheEarliestAdvance() {
        let lines = [
            LyricsLine(startTimeMs: 0, original: "previous", words: [
                LyricWordTiming(startTimeMs: 4_000, endTimeMs: 5_000, original: "previous")
            ]),
            LyricsLine(startTimeMs: 5_000, original: "next")
        ]
        let timing = LyricPullTiming.forLine(1, in: lines)
        #expect(LyricPullTiming.earliestAdvanceTimeMs(to: 1, in: lines) == 4_500)
        #expect(timing.advanceStartTimeMs(to: 1, in: lines) >= 4_500)
        #expect(timing.followDuration >= LyricPullTiming.minimumFollowDuration)
        #expect(timing.followDuration < LyricPullTiming.standard.followDuration)
    }

    @Test func veryLateTailWordMidpointStillLeavesAMinimumPullAndCompletionMargin() {
        let lines = [
            LyricsLine(startTimeMs: 0, original: "previous", words: [
                LyricWordTiming(startTimeMs: 4_950, endTimeMs: 5_050, original: "previous")
            ]),
            LyricsLine(startTimeMs: 5_000, original: "next")
        ]
        let timing = LyricPullTiming.forLine(1, in: lines)
        let trigger = timing.advanceStartTimeMs(to: 1, in: lines)
        #expect(timing.followDuration >= LyricPullTiming.minimumFollowDuration)
        #expect(trigger < 5_000)
        #expect(Double(trigger) + timing.followDuration * 1_000 <= 4_980)
    }

    @Test func firstGlyphBeforeTheLineTimestampSetsTheAdvanceDeadline() {
        let line = LyricsLine(startTimeMs: 3_000, original: "early", words: [
            LyricWordTiming(startTimeMs: 2_900, endTimeMs: 4_200, original: "early")
        ])
        #expect(LyricPullTiming.firstPlaybackTimeMs(for: line) == 2_900)
    }

    @Test func delayedFirstGlyphUsesItsOwnDeadlineInsteadOfTheLineHeader() {
        let lines = [
            LyricsLine(startTimeMs: 0, original: "previous", words: [
                LyricWordTiming(startTimeMs: 4_000, endTimeMs: 5_000, original: "previous")
            ]),
            LyricsLine(startTimeMs: 5_000, original: "next", words: [
                LyricWordTiming(startTimeMs: 5_800, endTimeMs: 6_500, original: "next")
            ])
        ]
        let timing = LyricPullTiming.forLine(1, in: lines)
        let trigger = timing.advanceStartTimeMs(to: 1, in: lines)
        #expect(LyricPullTiming.firstPlaybackTimeMs(for: lines[1]) == 5_800)
        #expect(trigger > lines[1].startTimeMs)
        #expect(Double(trigger) + timing.followDuration * 1_000 < 5_800)
    }

    @Test func completedLineStartsThePullAndFollowingDelaysGrowProgressively() {
        for timing in [LyricPullTiming.standard,
                       LyricPullTiming.standard.fittingBeforeFirstGlyph(remainingMs: 100)] {
            let origin = 10
            #expect(timing.delay(lineIndex: origin, originIndex: origin) == 0)
            #expect(timing.delay(lineIndex: origin - 3, originIndex: origin) == 0)
            #expect(abs(timing.delay(lineIndex: origin + 1, originIndex: origin)
                + timing.settleDuration - timing.followDuration) < 0.000001)
            var previousStep = 0.0
            for distance in 2...7 {
                let step = timing.delay(lineIndex: origin + distance, originIndex: origin)
                    - timing.delay(lineIndex: origin + distance - 1, originIndex: origin)
                #expect(step >= 0.055 - 0.000001)
                #expect(step > previousStep)
                previousStep = step
            }
            #expect(timing.totalDuration >= timing.delay(lineIndex: origin + 7, originIndex: origin)
                + timing.settleDuration(lineIndex: origin + 7, originIndex: origin))
        }
    }

    @Test @MainActor func oneWayPullStartsAtItsExistingPositionAndNeverMovesDownward() {
        let timing = LyricPullTiming.standard
        let velocities: [CGFloat] = [0, -120, -800]
        for velocity in velocities {
            for distance in 0...3 {
                let delay = timing.delay(lineIndex: distance, originIndex: 0)
                let settle = timing.settleDuration(lineIndex: distance, originIndex: 0)
                var previousOffset: CGFloat = 120
                for frame in 0...240 {
                    let elapsed = Double(frame) / 240 * timing.totalDuration
                    let motion = OneWayLyricPull.motion(initialOffset: 120, initialVelocity: velocity,
                                                       elapsed: elapsed, delay: delay, settleDuration: settle)
                    if frame == 0 { #expect(motion.offset == 120) }
                    #expect(motion.offset >= 0)
                    #expect(motion.offset <= previousOffset + 0.000001)
                    #expect(motion.velocity <= 0)
                    previousOffset = motion.offset
                }
                #expect(previousOffset == 0)
            }
        }
    }

    @Test func firstLetterLandsAsTheFinalLetterReachesItsPeak() {
        for count in [2, 5, 24, 40, 100] {
            let first = TailLetterMotion.state(progress: 0.74, letterIndex: 0, letterCount: count)
            let last = TailLetterMotion.state(progress: 0.74, letterIndex: count - 1, letterCount: count)
            #expect(abs(first.lift) < 0.000001)
            #expect(abs(last.lift - 6.2) < 0.000001)
            #expect(last.illumination == 1)
            #expect(abs(last.glow - 0.88) < 0.000001)
            for index in 1..<count {
                let landing = 0.74 + Double(index) / Double(count - 1) * 0.26
                let letter = TailLetterMotion.state(progress: landing, letterIndex: index, letterCount: count)
                #expect(abs(letter.lift) < 0.000001)
            }
        }
    }

    @Test func lettersKeepTheirGlowDuringTheSlowDescent() {
        let peak = TailLetterMotion.state(progress: 0.51, letterIndex: 0, letterCount: 8)
        let falling = TailLetterMotion.state(progress: 0.64, letterIndex: 0, letterCount: 8)
        #expect(peak.lift > falling.lift)
        #expect(falling.lift > 0)
        #expect(falling.glow == peak.glow)
        #expect(falling.illumination == 1)
    }

    @Test func letterRiseIsSlowerAndStartsGently() {
        let early = TailLetterMotion.state(progress: 0.12, letterIndex: 0, letterCount: 8)
        let halfway = TailLetterMotion.state(progress: 0.24, letterIndex: 0, letterCount: 8)
        let peak = TailLetterMotion.state(progress: 0.48, letterIndex: 0, letterCount: 8)
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
