import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleMorphTests {
    @Test func bothGlyphsFollowTheSameDirectRouteAtEveryProgress() throws {
        let old: [LiveLyricsParticleHome] = [.init(id: 4, x: 80, y: 10), .init(id: 9, x: 10, y: 20)]
        let next: [LiveLyricsParticleHome] = [.init(id: 2, x: 150, y: 40), .init(id: 7, x: 30, y: 12)]
        let outgoing = LiveLyricsParticleRoutes.offsets(from: old, to: next)
        let incoming = LiveLyricsParticleRoutes.offsets(from: next, to: old)
        // Spatial order, not IDs or array order, pairs the actual ink homes.
        for (source, target) in [(old[0], next[0]), (old[1], next[1])] {
            let exit = try #require(outgoing[source.id])
            let entry = try #require(incoming[target.id])
            for progress in [0.0, 0.1, 0.35, 0.5, 0.8, 1.0, 1.08] {
                // Include spring overshoot. Old and new must coincide all
                // along the route, not meet at a separate scatter endpoint.
                #expect(abs(source.x + exit.x * progress - (target.x + entry.x * (1 - progress))) < 0.000001)
                #expect(abs(source.y + exit.y * progress - (target.y + entry.y * (1 - progress))) < 0.000001)
            }
        }
    }

    @Test func changingDensityStillRoutesOnlyToRealGlyphHomes() throws {
        let source = (0..<12).map { LiveLyricsParticleHome(id: $0, x: Double($0 * 5), y: 10) }
        let target = (0..<5).map { LiveLyricsParticleHome(id: $0 + 20, x: Double($0 * 20), y: 30) }
        for (from, to) in [(source, target), (target, source)] {
            let routes = LiveLyricsParticleRoutes.offsets(from: from, to: to)
            #expect(routes.count == from.count)
            for home in from {
                let delta = try #require(routes[home.id])
                #expect(to.contains { abs($0.x - home.x - delta.x) < 0.000001
                    && abs($0.y - home.y - delta.y) < 0.000001 })
            }
        }
        #expect(LiveLyricsParticleRoutes.offsets(from: source, to: source).values.allSatisfy { $0 == .zero })
        #expect(LiveLyricsParticleRoutes.offsets(from: source, to: []).isEmpty)
    }

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
