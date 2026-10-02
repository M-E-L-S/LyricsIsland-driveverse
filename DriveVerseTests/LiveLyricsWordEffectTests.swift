import Foundation
import Testing
@testable import DriveVerse

#if !os(iOS)
@Suite @MainActor struct LiveLyricsWordEffectPreferenceTests {
    @Test func existingInstallKeepsFillAndClassicSelectionPersistsIndependently() throws {
        let suite = "DriveVerseTests.wordEffect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        #expect(model.liveActivityWordEffect == .fill)
        model.liveActivityWordEffect = .classic
        #expect(AppModel(defaults: defaults).liveActivityWordEffect == .classic)
        model.liveActivityLineEffect = .particles
        model.liveActivityWordUpdatesEnabled = false
        model.liveActivityWordUpdatesEnabled = true
        #expect(model.liveActivityWordEffect == .classic)
        model.liveActivityWordEffect = .fill
        let reopened = AppModel(defaults: defaults)
        #expect(reopened.liveActivityWordEffect == .fill)
        #expect(reopened.liveActivityLineEffect == .particles)
    }

    @Test func unknownStoredEffectFallsBackToFill() throws {
        let suite = "DriveVerseTests.wordEffect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-effect", forKey: "liveActivityWordEffect")
        #expect(AppModel(defaults: defaults).liveActivityWordEffect == .fill)
    }
}
#endif

#if canImport(ActivityKit) && os(iOS)
@Suite struct LiveLyricsWordEffectStateTests {
    @Test func oldArchivedStateRemainsFillCompatibleAndNewMetadataRoundTrips() throws {
        var state = LyricsAttributes.ContentState(
            title: "Song", artist: "Artist", artworkData: nil,
            secondaryLine: "", nextLine: "下一句",
            completedText: "love", activeText: "", remainingText: "",
            lyricPositionMs: 500, positionDate: Date(timeIntervalSince1970: 0),
            activeWordStartMs: 0, activeWordEndMs: 2_000,
            fillTarget: 1, fillAnimationDurationMs: 1_500,
            lineIndex: 0, usesWordTiming: true, lineMarqueeAtEnd: false,
            lineMarqueeDurationMs: 0, isPlaying: true
        )
        let old = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LyricsAttributes.ContentState.self, from: old)
        #expect(decoded.wordEffect == nil && decoded.tailWord == nil && decoded.tailProgress == nil)
        state.wordEffect = .fill
        state.tailWord = LiveLyricsTailWord.make(characterStart: 0, startMs: 0, endMs: 2_000)
        state.tailProgress = 0.48
        state.tailAnimationDurationMs = 600
        let restored = try JSONDecoder().decode(LyricsAttributes.ContentState.self,
                                                from: JSONEncoder().encode(state))
        #expect(restored == state)
        state.wordEffect = .classic
        state.tailWord = nil
        state.tailProgress = nil
        state.tailAnimationDurationMs = nil
        #expect(try JSONDecoder().decode(LyricsAttributes.ContentState.self,
            from: JSONEncoder().encode(state)).wordEffect == .classic)
    }
}
#endif
