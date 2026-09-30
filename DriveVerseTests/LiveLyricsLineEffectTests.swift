import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleTimingTests {
    @Test func normalAndUnknownLineDurationsAllowGathering() {
        #expect(LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: 3_000))
        #expect(LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: nil))
    }

    @Test func fastLinesAndSeeksNearTheTailStayReadable() {
        #expect(!LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: 300))
        #expect(!LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: 0))
        #expect(!LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: -10))
    }

    @Test func outgoingGlyphsDisperseBeforeTheInvisibleSwapAndGather() {
        let steps = LiveLyricsParticleStep.transition(from: "旧句", to: "新句")
        #expect(steps.count == 3)
        #expect(steps[0].text == "旧句")
        #expect(steps[0].phase == .dispersing)
        #expect(steps[0].delay == 0)
        #expect(steps[1].text == "新句")
        #expect(steps[1].phase == .staged)
        #expect(steps[1].delay > LiveLyricsAnimationTiming.particleDisperseDuration)
        #expect(steps[2].text == steps[1].text)
        #expect(steps[2].phase == .settled)
        #expect(steps[2].delay >= 0.2)
    }

    @Test func firstLineOrInterruptedTransitionStagesOnlyIncomingGlyphs() {
        let missingOutgoing: [String?] = [nil, ""]
        for outgoing in missingOutgoing {
            let steps = LiveLyricsParticleStep.transition(from: outgoing, to: "新句")
            #expect(steps.map(\.phase) == [.staged, .settled])
            #expect(steps.map(\.text) == ["新句", "新句"])
            #expect(steps.first?.delay == 0)
        }
    }

    @Test func durationBudgetIncludesBothAnimationsAndTheInvisibleSwap() {
        let steps = LiveLyricsParticleStep.transition(from: "旧句", to: "新句")
        let milliseconds = Int(ceil((steps.reduce(0) { $0 + $1.delay }
            + LiveLyricsAnimationTiming.particleGatherDuration
            + 5 * LiveLyricsAnimationTiming.particleStaggerStep) * 1_000))
        #expect(LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: milliseconds))
        #expect(!LiveLyricsAnimationTiming.canAnimateParticles(remainingMs: milliseconds - 2))
    }
}

#if !os(iOS)
// AppModel's iOS initializer owns real Live Activities; preference tests use
// the macOS harness so they cannot end an existing device activity.
@Suite @MainActor struct LiveLyricsLineEffectPreferenceTests {
    @Test func defaultsToOriginalAndPersistsParticleSelectionAcrossLaunches() throws {
        let suite = "DriveVerseTests.lineEffect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        #expect(model.liveActivityLineEffect == .original)

        model.liveActivityLineEffect = .particles
        #expect(AppModel(defaults: defaults).liveActivityLineEffect == .particles)
        model.liveActivityWordUpdatesEnabled = false
        model.liveActivityWordUpdatesEnabled = true
        #expect(model.liveActivityLineEffect == .particles)

        model.liveActivityLineEffect = .original
        #expect(AppModel(defaults: defaults).liveActivityLineEffect == .original)
    }

    @Test func unknownStoredEffectFallsBackToOriginal() throws {
        let suite = "DriveVerseTests.lineEffect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown-effect", forKey: "liveActivityLineEffect")
        #expect(AppModel(defaults: defaults).liveActivityLineEffect == .original)
    }
}
#endif

#if canImport(ActivityKit) && os(iOS)
@Suite struct LiveLyricsLineEffectStateTests {
    private func state() -> LyricsAttributes.ContentState {
        LyricsAttributes.ContentState(
            title: "Song", artist: "Artist", artworkData: nil,
            secondaryLine: "", nextLine: "下一行",
            completedText: "当前歌词", activeText: "", remainingText: "",
            lyricPositionMs: 0, positionDate: Date(timeIntervalSince1970: 0),
            activeWordStartMs: 0, activeWordEndMs: 0,
            fillTarget: 0, fillAnimationDurationMs: 0,
            lineIndex: 0, usesWordTiming: false, lineMarqueeAtEnd: false,
            lineMarqueeDurationMs: 0, isPlaying: true
        )
    }

    @Test func oldArchivedStateKeepsOriginalEffect() throws {
        let data = try JSONEncoder().encode(state())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["j"] == nil)
        #expect(object["k"] == nil)
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self, from: data)
        #expect(decoded.lineEffect == nil)
        #expect(!decoded.usesLineParticles)
        #expect(decoded.particlesAreSettled)
    }

    @Test func scatteredAndSettledEndpointsSurviveArchiving() throws {
        var content = state()
        content.lineEffect = .particles
        content.lineParticlesSettled = false
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let scattered = try decoder.decode(LyricsAttributes.ContentState.self, from: encoder.encode(content))
        #expect(scattered.usesLineParticles)
        #expect(!scattered.particlesAreSettled)
        content.lineParticlesSettled = true
        let settled = try decoder.decode(LyricsAttributes.ContentState.self, from: encoder.encode(content))
        #expect(settled.particlesAreSettled)
        #expect(scattered != settled)
        #expect(scattered.completedText == settled.completedText)
        #expect(scattered.lineIndex == settled.lineIndex)
    }

    @Test func particlesRequireLineModeAndARealLyric() throws {
        var content = state()
        content.lineEffect = .particles
        let data = try JSONEncoder().encode(content)
        #expect(try JSONDecoder().decode(LyricsAttributes.ContentState.self, from: data).usesLineParticles)
        content.usesWordTiming = true
        #expect(!content.usesLineParticles)
        content.usesWordTiming = false
        content.lineIndex = nil
        #expect(!content.usesLineParticles)
        content.lineIndex = 0
        content.completedText = ""
        #expect(!content.usesLineParticles)
    }

    @Test func particleCanvasRetainsOutgoingTextWithoutDelayingOtherFamilies() throws {
        var content = state()
        content.lineEffect = .particles
        content.completedText = "新句"
        let steps = LiveLyricsParticleStep.transition(from: "旧句", to: "新句")
        for step in steps {
            content.applyParticleStep(step)
            let decoded = try JSONDecoder().decode(
                LyricsAttributes.ContentState.self, from: JSONEncoder().encode(content)
            )
            #expect(decoded.completedText == "新句")
            #expect(decoded.particleDisplayedText == step.text)
            #expect(decoded.particlePhase == step.phase)
            #expect(decoded.particlesAreSettled == (step.phase == .settled))
        }
        #expect(content.lineParticleText == nil)
    }
}
#endif
