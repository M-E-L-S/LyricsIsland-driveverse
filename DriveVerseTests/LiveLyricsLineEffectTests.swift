import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleTimingTests {
    @Test func homepageSpringSettlesWithinWidgetKitDurationLimit() {
        #expect(LiveLyricsParticlePhysics.stiffness == 60 * 2.4)
        #expect(abs(LiveLyricsParticlePhysics.damping - (3 + 12 * 0.85)) < 0.0001)
        #expect(LiveLyricsParticlePhysics.settlingDuration < 2)
        let envelope = exp(-LiveLyricsParticlePhysics.damping / 2
                           * LiveLyricsParticlePhysics.settlingDuration)
        #expect(envelope < 0.001)
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
    @Test func naturalAdvanceSharesTheExactSourceAndDestinationWithoutPreparation() throws {
        var old = state()
        old.lineEffect = .particles
        old.nextLine = "新句"
        old.particleMorphRevision = 10
        var next = old
        next.completedText = "新句"
        next.nextLine = "再下一句"
        next.particleMorphRevision = 11
        #expect(next.prepareParticleTransition(from: old) == nil)
        #expect(next.particleMorphEnabled == true)
        #expect(next.particlePreviousText == old.particleLineIdentity.text)
        #expect(old.nextLine == next.particleLineIdentity.text)
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self,
                                               from: JSONEncoder().encode(next))
        #expect(decoded.particlePreviousText == old.particleLineIdentity.text)
        // Metadata/marquee refreshes must not replay the same journey.
        var refreshed = next
        refreshed.artist = "Updated artist"
        #expect(refreshed.prepareParticleTransition(from: next) == nil)
        #expect(refreshed.particleMorphEnabled == false)
        #expect(refreshed.particleMorphRevision == 11)
    }

    @Test func unexpectedSeekUpdatesOnlyTheOldDestinationBeforeChangingGlyphs() throws {
        var old = state()
        old.lineEffect = .particles
        old.particleMorphRevision = 4
        old.particleMorphEnabled = true
        old.particlePreviousText = "更早的歌词"
        var seek = old
        seek.completedText = "跳转后的歌词"
        seek.particleMorphRevision = 6 // A superseded proposal need not be shown.
        let prepared = try #require(seek.prepareParticleTransition(from: old))
        #expect(prepared.particleLineIdentity == old.particleLineIdentity)
        #expect(prepared.particleMorphRevision == old.particleMorphRevision)
        #expect(prepared.particleMorphEnabled == false)
        #expect(prepared.particlePreviousText == nil)
        #expect(prepared.nextLine == seek.particleLineIdentity.text)
        #expect(seek.particlePreviousText == old.particleLineIdentity.text)
        #expect(seek.particleMorphEnabled == true)
        #expect(seek.prepareParticleTransition(from: prepared) == nil)
        #expect(seek.particleMorphEnabled == true)
    }

    @Test func pausedAndInitialStatesHaveNoDeferredMorph() {
        var initial = state()
        initial.lineEffect = .particles
        #expect(initial.prepareParticleTransition(from: nil) == nil)
        #expect(initial.particleMorphEnabled == false)
        var paused = initial
        paused.completedText = "暂停时换句"
        paused.isPlaying = false
        #expect(paused.prepareParticleTransition(from: initial) == nil)
        #expect(paused.particlePreviousText == nil)
        var resumed = paused
        resumed.isPlaying = true
        #expect(resumed.prepareParticleTransition(from: paused) == nil)
        #expect(resumed.particleMorphEnabled == false)
    }

    @Test func morphContextFitsNormalPayloadsAndCannotOverflowLargeOnes() throws {
        var content = state()
        content.lineEffect = .particles
        content.title = String(repeating: "歌", count: 48)
        content.artist = String(repeating: "人", count: 48)
        content.secondaryLine = String(repeating: "译", count: 72)
        content.nextLine = String(repeating: "下", count: 72)
        content.completedText = String(repeating: "词", count: 100)
        content.artworkData = Data(repeating: 0, count: 1_600)
        content.particlePreviousText = String(repeating: "前", count: 100)
        content.particleMorphEnabled = true
        content.boundParticleContext()
        #expect(content.particlePreviousText != nil)
        #expect(try JSONEncoder().encode(content).count <= 4_000)
        content.particlePreviousText = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        content.boundParticleContext()
        #expect(content.particlePreviousText == nil)
        #expect(content.particleMorphEnabled == false)
        #expect(content.completedText.count == 100)
        #expect(content.artworkData?.count == 1_600)
        #expect(try JSONEncoder().encode(content).count <= 4_000)
    }

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
        #expect(object["u"] == nil)
        #expect(object["y"] == nil)
        #expect(object["z"] == nil)
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self, from: data)
        #expect(decoded.lineEffect == nil)
        #expect(decoded.particleMorphEnabled == nil)
        #expect(decoded.particlePreviousText == nil)
        #expect(!decoded.usesLineParticles)
    }

    @Test func nonLyricUpdatesDoNotRestartParticleTransitions() {
        var content = state()
        content.lineEffect = .particles
        let identity = content.particleLineIdentity
        content.lyricPositionMs = 1_000
        content.positionDate = Date(timeIntervalSince1970: 1)
        content.fillTarget = 2
        content.lineMarqueeAtEnd = true
        content.isPlaying = false
        content.secondaryLine = "translation"
        content.nextLine = "updated next line"
        content.title = "Refined title"
        content.artist = "Refined artist"
        content.artworkData = Data([1, 2, 3])
        #expect(content.particleLineIdentity == identity)
    }

    @Test func onlyDifferentGlyphsReceiveNewIdentities() {
        let content = state()
        var changed = content
        changed.completedText = "新的歌词"
        #expect(changed.particleLineIdentity != content.particleLineIdentity)
        changed = content
        changed.lineIndex = 1
        #expect(changed.particleLineIdentity == content.particleLineIdentity)
    }

    @Test func marqueeUpdateDisablesMorphAndPreservesItsRevision() throws {
        var tracker = LiveLyricsParticleMorphTracker()
        _ = tracker.prepare(text: "旧句", animate: false)
        var content = state()
        content.lineEffect = .particles
        let plan = tracker.prepare(text: content.particleLineIdentity.text, animate: true)
        content.applyParticleMorph(plan)
        #expect(content.particleMorphEnabled == true)
        let revision = content.particleMorphRevision
        content.lineMarqueeAtEnd = true
        content.stopParticleMorph()
        #expect(content.particleMorphEnabled == false)
        #expect(content.particleMorphRevision == revision)
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self,
                                               from: JSONEncoder().encode(content))
        #expect(decoded.particleMorphEnabled == false)
        #expect(decoded.particleMorphRevision == revision)
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

    @Test func legacyIntermediatePhasesCannotHideOrReplaceTheCurrentLyric() throws {
        var content = state()
        content.lineEffect = .particles
        content.completedText = "新句"
        let encoded = try JSONEncoder().encode(content)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["k"] = false
        object["o"] = "旧句"
        object["c"] = 2
        let decoded = try JSONDecoder().decode(
            LyricsAttributes.ContentState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.usesLineParticles)
        #expect(decoded.particleLineIdentity.text == "新句")
    }
}
#endif
