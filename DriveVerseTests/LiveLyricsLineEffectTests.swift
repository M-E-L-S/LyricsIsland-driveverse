import Foundation
import Testing
@testable import DriveVerse

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
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self, from: data)
        #expect(decoded.lineEffect == nil)
        #expect(!decoded.usesLineParticles)
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
}
#endif
