import Testing
@testable import DriveVerse

@Suite struct LiveLyricsTailAnimationTests {
    @Test func heldWordEligibilityMatchesFullScreenThreshold() throws {
        #expect(LiveLyricsTailWord.make(characterStart: 2, startMs: 500, endMs: 1_699) == nil)
        #expect(LiveLyricsTailWord.make(characterStart: -1, startMs: 0, endMs: 2_000) == nil)
        #expect(LiveLyricsTailWord.make(characterStart: 0, startMs: 2_000, endMs: 1_000) == nil)
        let word = try #require(LiveLyricsTailWord.make(characterStart: 2, startMs: 500, endMs: 1_700))
        #expect(word.progress(at: 644) == 0)
        #expect(word.progress(at: 1_700) == 1)
        #expect(word.progress(at: 2_000) == 1)
        #expect(abs(word.progress(at: word.position(at: 0.5)) - 0.5) < 0.001)
    }

    @Test func waitsForSingingAndShortHeldWordsStillGetALiftEndpoint() throws {
        let word = try #require(LiveLyricsTailWord.make(characterStart: 0, startMs: 1_000, endMs: 2_200))
        #expect(LiveLyricsTailAnimation.next(word: word, at: 1_000, after: 0)
                == .wait(milliseconds: 144))
        guard case .animate(let progress, let duration)? = LiveLyricsTailAnimation.next(
            word: word, at: 1_144, after: 0
        ) else { Issue.record("Missing held-word lift"); return }
        #expect(duration >= 180 && duration <= 2_000)
        let first = TailLetterMotion.state(progress: progress, letterIndex: 0, letterCount: 6)
        #expect(first.lift > 6)
        #expect(first.glow > 0.8)
    }

    @Test func delayedEndpointsStayMonotonicAndWithinSystemDurationLimit() throws {
        for duration in [1_200, 2_400, 5_000, 12_000] {
            let word = try #require(LiveLyricsTailWord.make(characterStart: 3, startMs: 0, endMs: duration))
            var position = word.position(at: 0)
            var target = 0.0
            var phases = 0
            while let step = LiveLyricsTailAnimation.next(word: word, at: position, after: target) {
                phases += 1
                #expect(phases < 100)
                if phases >= 100 { break }
                switch step {
                case .wait(let milliseconds):
                    #expect(milliseconds > 0)
                    position += milliseconds
                case .animate(let progress, let milliseconds):
                    #expect(progress > target && progress <= 1)
                    #expect(milliseconds > 0 && milliseconds <= 2_000)
                    target = progress
                    // Include delivery delay and a handoff before completion.
                    position += max(1, milliseconds - 30) + 120
                }
            }
            #expect(target == 1)
            #expect(LiveLyricsTailAnimation.next(word: word, at: duration + 500, after: target) == nil)
        }
    }

    @Test func nonLatinTailRisesGlowsAndReturnsToBaseline() {
        let start = LiveLyricsTailAnimation.wholeWordMotion(progress: 0)
        let peak = LiveLyricsTailAnimation.wholeWordMotion(progress: 0.5)
        let end = LiveLyricsTailAnimation.wholeWordMotion(progress: 1)
        #expect(start.lift == 0 && start.glow == 0)
        #expect(abs(peak.lift - 6.2) < 0.000001)
        #expect(abs(peak.glow - 0.88) < 0.000001)
        #expect(abs(end.lift) < 0.000001 && abs(end.glow) < 0.000001)
        #expect(peak.illumination == 0)
    }

    @Test func lockScreenLiftIsSubtleAndNeverBypassesTheFillMask() throws {
        for usesLetters in [false, true] {
            for index in 0..<6 {
                for frame in 0...100 {
                    let motion = LiveLyricsTailAnimation.motion(progress: Double(frame) / 100,
                        letterIndex: index, letterCount: 6, usesLetterMotion: usesLetters)
                    #expect(motion.lift >= 0 && motion.lift <= 2.000001)
                    #expect(motion.illumination == 0)
                    if frame == 100 {
                        #expect(abs(motion.lift) < 0.000001 && abs(motion.glow) < 0.000001)
                    }
                }
            }
        }
        let word = try #require(LiveLyricsTailWord.make(characterStart: 2, startMs: 800, endMs: 3_200))
        #expect(!LiveLyricsTailAnimation.showsFilledTail(target: 0, word: word))
        #expect(!LiveLyricsTailAnimation.showsFilledTail(target: 2, word: word))
        #expect(LiveLyricsTailAnimation.showsFilledTail(target: 2.1, word: word))
    }
}
