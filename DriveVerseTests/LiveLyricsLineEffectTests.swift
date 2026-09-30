import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveLyricsParticleTimingTests {
    @Test func nativeTransitionsDoNotOverlapAndStayWithinWidgetKitDurationLimit() {
        #expect(LiveLyricsAnimationTiming.particleGatherDelay
            >= LiveLyricsAnimationTiming.particleDisperseDuration)
        let total = LiveLyricsAnimationTiming.particleGatherDelay
            + LiveLyricsAnimationTiming.particleGatherDuration
            + 5 * LiveLyricsAnimationTiming.particleStaggerStep
        #expect(total < 2)
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
    }

    @Test func nonLyricUpdatesDoNotRestartTileTransitions() {
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
        #expect(content.particleLineIdentity == identity)
    }

    @Test func newGlyphsAndRepeatedLyricLinesReceiveNewIdentities() {
        let content = state()
        var changed = content
        changed.completedText = "新的歌词"
        #expect(changed.particleLineIdentity != content.particleLineIdentity)
        changed = content
        changed.lineIndex = 1
        #expect(changed.particleLineIdentity != content.particleLineIdentity)
        changed = content
        changed.title = "Another Song"
        #expect(changed.particleLineIdentity != content.particleLineIdentity)
        changed = content
        changed.artist = "Another Artist"
        #expect(changed.particleLineIdentity != content.particleLineIdentity)
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
