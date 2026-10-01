import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleMorphTests {
    @Test func initialTextAndSameTextUpdatesNeverStartAnotherMorph() {
        var tracker = LiveLyricsParticleMorphTracker()
        let initial = tracker.prepare(text: "初始句", animate: true)
        #expect(!initial.animates)
        let next = tracker.prepare(text: "下一句", animate: true)
        #expect(next.animates)
        #expect(next.previousText == "初始句")
        // Marquee tail, metadata refresh, same lyric at a new line index,
        // preference forceNextUpdate and pause/resume all retain the text.
        for enabled in [true, true, true, true, false, true] {
            let repeated = tracker.prepare(text: "下一句", animate: enabled)
            #expect(!repeated.animates)
            #expect(repeated.previousText == nil)
            #expect(repeated.revision == next.revision)
        }
        let last = tracker.prepare(text: "最后一句", animate: true)
        #expect(last.animates)
        #expect(last.revision == next.revision + 1)
    }

    @Test func rapidChangesRetargetAndReturningToAnEarlierTextStillMorphs() {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.prepare(text: "A", animate: false)
        let toB = tracker.prepare(text: "B", animate: true)
        let toC = tracker.prepare(text: "C", animate: true)
        let toA = tracker.prepare(text: "A", animate: true)
        #expect(toB.animates && toC.animates && toA.animates)
        #expect(toC.previousText == "B")
        #expect(toA.previousText == "C")
        #expect(toA.revision == toB.revision + 2)
    }

    @Test func pausedOrEmptyChangesHaveNoDeferredReplay() {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.prepare(text: "旧句", animate: false)
        let paused = tracker.prepare(text: "新句", animate: false)
        let resumed = tracker.prepare(text: "新句", animate: true)
        let blank = tracker.prepare(text: "", animate: true)
        let afterBlank = tracker.prepare(text: "另一句", animate: true)
        #expect(!paused.animates && !resumed.animates)
        #expect(!blank.animates && !afterBlank.animates)
        #expect(resumed.revision == paused.revision)
    }

    @Test func archivedScatterDirectionsAreDeterministicAndVaried() {
        let first = (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 0) }
        let repeated = (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 0) }
        #expect(first == repeated)
        #expect(first.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(Set(first).count == first.count)
        #expect(first != (0..<100).map { LiveLyricsParticlePhysics.randomUnit(index: $0, salt: 1) })
    }
}
