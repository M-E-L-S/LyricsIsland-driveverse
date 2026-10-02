import Foundation
import Testing
@testable import DriveVerse

@Suite struct LiveActivityLineTimingTests {
    private let lines = [
        LyricsLine(startTimeMs: 0, original: "上一句"),
        LyricsLine(startTimeMs: 10_000, original: "下一句", words: [
            LyricWordTiming(startTimeMs: 10_000, endTimeMs: 10_500, original: "下"),
            LyricWordTiming(startTimeMs: 10_500, endTimeMs: 11_000, original: "一句"),
        ]),
        LyricsLine(startTimeMs: 20_000, original: "再下一句"),
    ]

    @Test func originalAndWordModesTriggerOnlyHalfASecondEarly() {
        for wordMode in [false, true] {
            let lead = LiveLyricsAnimationTiming.lineTriggerLeadMs(
                wordUpdatesEnabled: wordMode, lineEffect: .original
            )
            #expect(lead == 500)
            let before = SyncEngine.position(atMs: 9_499, lines: lines,
                durationMs: nil, isPlaying: true, lineLookaheadMs: lead)
            let boundary = SyncEngine.position(atMs: 9_500, lines: lines,
                durationMs: nil, isPlaying: true, lineLookaheadMs: lead)
            #expect(before.lineIndex == 0)
            #expect(boundary.lineIndex == 1)
            #expect(boundary.currentWordIndex == 0)
            #expect(boundary.positionMs == 9_500)
            #expect(boundary.lyricPositionMs == 9_500)
            #expect(LiveLyricsFillTimeline.progress(
                words: boundary.currentWords ?? [], at: boundary.lyricPositionMs
            ) == 0)
        }
    }

    @Test func particleModeStartsAnotherTwoHundredMillisecondsLater() {
        let lead = LiveLyricsAnimationTiming.lineTriggerLeadMs(
            wordUpdatesEnabled: false, lineEffect: .particles
        )
        #expect(lead == 950)
        let before = SyncEngine.position(atMs: 9_049, lines: lines,
            durationMs: nil, isPlaying: true, lineLookaheadMs: lead)
        let boundary = SyncEngine.position(atMs: 9_050, lines: lines,
            durationMs: nil, isPlaying: true, lineLookaheadMs: lead)
        #expect(before.lineIndex == 0)
        #expect(boundary.lineIndex == 1)
        // Choosing particles does not change timing while word mode is active.
        #expect(LiveLyricsAnimationTiming.lineTriggerLeadMs(
            wordUpdatesEnabled: true, lineEffect: .particles
        ) == 500)
    }

    @Test func deadlineAvoidsWaitingForTheNextPeriodicSample() {
        #expect(SyncEngine.nextLiveActivityRefreshMs(
            at: 9_400, lines: lines, leadMs: 500
        ) == 9_500)
        #expect(SyncEngine.nextLiveActivityRefreshMs(
            at: 9_500, lines: lines, leadMs: 500
        ) == 10_000)
        #expect(SyncEngine.nextLiveActivityRefreshMs(
            at: 10_000, lines: lines, leadMs: 500
        ) == 19_500)
    }

    @Test func pausedPlaybackAndAppLyricsDoNotLookAhead() {
        let actual = SyncEngine.position(atMs: 9_700, lines: lines,
            durationMs: nil, isPlaying: true)
        let paused = SyncEngine.position(atMs: 9_700, lines: lines,
            durationMs: nil, isPlaying: false, lineLookaheadMs: 1_350)
        #expect(actual.lineIndex == 0)
        #expect(paused.lineIndex == 0)
    }

    @Test func timingOffsetStillAppliesToBothClocks() {
        let position = SyncEngine.position(atMs: 10_500, lines: lines,
            durationMs: nil, isPlaying: true, offsetMs: 1_000, lineLookaheadMs: 500)
        #expect(position.positionMs == 10_500)
        #expect(position.lyricPositionMs == 9_500)
        #expect(position.lineIndex == 1)
        #expect(position.currentWordIndex == 0)
    }

    @Test func longLookaheadDoesNotSkipShortLines() {
        let short = [
            LyricsLine(startTimeMs: 0, original: "一"),
            LyricsLine(startTimeMs: 200, original: "二"),
            LyricsLine(startTimeMs: 400, original: "三"),
        ]
        let position = SyncEngine.position(atMs: 100, lines: short,
            durationMs: nil, isPlaying: true, lineLookaheadMs: 1_350)
        #expect(position.lineIndex == 1)
    }

    @Test func engineKeepsAppAndActivityPositionsSeparateAcrossPauseAndSeek() {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let engine = SyncEngine(now: { now })
        engine.setLyrics(lines)
        engine.setLiveActivityLineLeadMs(500)
        func playback(_ position: Int, playing: Bool) -> NowPlayingState {
            NowPlayingState(title: "Track", artist: "Artist", album: nil,
                durationMs: nil, positionMs: position, isPlaying: playing, capturedAt: now)
        }
        engine.apply(playback(9_500, playing: true))
        #expect(engine.positionSubject.value?.lineIndex == 0)
        #expect(engine.liveActivityPositionSubject.value?.lineIndex == 1)
        engine.apply(playback(9_500, playing: false))
        #expect(engine.liveActivityPositionSubject.value?.lineIndex == 0)
        now = now.addingTimeInterval(1)
        engine.apply(playback(500, playing: true))
        #expect(engine.liveActivityPositionSubject.value?.lineIndex == 0)
        engine.apply(nil)
        #expect(engine.liveActivityPositionSubject.value == nil)
    }
}
