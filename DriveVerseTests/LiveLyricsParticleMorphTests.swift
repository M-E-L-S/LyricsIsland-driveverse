import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleMorphTests {
    @Test func cancelledSendCannotConsumeTheNextLyricTransition() {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.recordSubmission(text: "已显示", animate: false)
        // sync() plans this send, then a newer sync cancels its generation.
        let cancelled = tracker.plan(text: "下一句", animate: true)
        let replacement = tracker.plan(text: "下一句", animate: true)
        #expect(cancelled.animates)
        #expect(replacement == cancelled)
        let submitted = tracker.recordSubmission(text: "下一句", animate: true)
        #expect(submitted == cancelled)
        #expect(submitted.previousText == "已显示")
        #expect(!tracker.recordSubmission(text: "下一句", animate: true).animates)
    }

    @Test func coalescedLyricsStartFromTheLastSubmittedText() {
        var tracker = LiveLyricsParticleMorphTracker()
        let initial = tracker.recordSubmission(text: "A", animate: false)
        _ = tracker.plan(text: "B", animate: true)
        _ = tracker.plan(text: "C", animate: true)
        _ = tracker.plan(text: "C", animate: true)
        // B was superseded, and none of those proposals reached ActivityKit.
        let newest = tracker.recordSubmission(text: "C", animate: true)
        #expect(newest.animates)
        #expect(newest.previousText == "A")
        #expect(newest.revision == initial.revision + 1)
        #expect(!tracker.plan(text: "C", animate: true).animates)
    }

    @Test func initialTextAndSameTextUpdatesNeverStartAnotherMorph() {
        var tracker = LiveLyricsParticleMorphTracker()
        let initial = tracker.recordSubmission(text: "初始句", animate: true)
        #expect(!initial.animates)
        let next = tracker.recordSubmission(text: "下一句", animate: true)
        #expect(next.animates)
        #expect(next.previousText == "初始句")
        // Marquee tail, metadata refresh, same lyric at a new line index,
        // preference forceNextUpdate and pause/resume all retain the text.
        for enabled in [true, true, true, true, false, true] {
            let repeated = tracker.recordSubmission(text: "下一句", animate: enabled)
            #expect(!repeated.animates)
            #expect(repeated.previousText == nil)
            #expect(repeated.revision == next.revision)
        }
        let last = tracker.recordSubmission(text: "最后一句", animate: true)
        #expect(last.animates)
        #expect(last.revision == next.revision + 1)
    }

    @Test func rapidChangesRetargetAndReturningToAnEarlierTextStillMorphs() {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.recordSubmission(text: "A", animate: false)
        let toB = tracker.recordSubmission(text: "B", animate: true)
        let toC = tracker.recordSubmission(text: "C", animate: true)
        let toA = tracker.recordSubmission(text: "A", animate: true)
        #expect(toB.animates && toC.animates && toA.animates)
        #expect(toC.previousText == "B")
        #expect(toA.previousText == "C")
        #expect(toA.revision == toB.revision + 2)
    }

    @Test func pausedOrEmptyChangesHaveNoDeferredReplay() {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.recordSubmission(text: "旧句", animate: false)
        let paused = tracker.recordSubmission(text: "新句", animate: false)
        let resumed = tracker.recordSubmission(text: "新句", animate: true)
        let blank = tracker.recordSubmission(text: "", animate: true)
        let afterBlank = tracker.recordSubmission(text: "另一句", animate: true)
        #expect(!paused.animates && !resumed.animates)
        #expect(!blank.animates && !afterBlank.animates)
        #expect(resumed.revision == paused.revision)
    }

    @Test func archivedSamplingIsDeterministicAndVaried() {
        let first = (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 0) }
        let repeated = (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 0) }
        #expect(first == repeated)
        #expect(first.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(Set(first).count == first.count)
        #expect(first != (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 1) })
    }
}
