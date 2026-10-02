import Foundation
import Combine

struct LyricsPosition: Equatable {
    let positionMs: Int
    let lyricPositionMs: Int
    let lineIndex: Int?
    let currentLine: String?
    let currentSecondaryLine: String?
    let currentWords: [LyricWordTiming]?
    let currentWordIndex: Int?
    let nextLine: String?
    let nextSecondaryLine: String?
    /// Remaining time in the current lyric line's display window.
    let currentLineRemainingMs: Int?
    /// 0–1 through the current line's time window.
    let lineProgress: Double
    /// 0–1 through the whole track.
    let trackProgress: Double
    let isPlaying: Bool
}

/// Extrapolates playback position between Apple Music reports and maps the
/// position to the current LRC line index.
/// The clock is injected so every code path is unit-testable.
final class SyncEngine {
    static let seekThresholdMs = 2000
    /// Intentionally aggressive while testing word-level ActivityKit updates.
    /// The Live Activity policy still suppresses unchanged word/line states.
    static let tickInterval: TimeInterval = 0.25

    var now: () -> Date
    private(set) var anchor: NowPlayingState?
    private(set) var lines: [LyricsLine] = []
    private(set) var displayOptions = LyricsDisplayOptions()
    private(set) var offsetMs = 0
    let positionSubject = CurrentValueSubject<LyricsPosition?, Never>(nil)
    let liveActivityPositionSubject = CurrentValueSubject<LyricsPosition?, Never>(nil)
    private var timer: AnyCancellable?
    private var liveActivityBoundaryTask: Task<Void, Never>?
    private var liveActivityLineLeadMs = 0

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func setLyrics(_ lines: [LyricsLine]) {
        self.lines = lines
        tick()
    }

    func setDisplayOptions(_ options: LyricsDisplayOptions) {
        displayOptions = options
        tick()
    }

    /// Positive values delay lyrics; negative values show them earlier.
    func setOffsetMs(_ value: Int) {
        offsetMs = min(5_000, max(-5_000, value))
        tick()
    }

    func setLiveActivityLineLeadMs(_ value: Int) {
        liveActivityLineLeadMs = max(0, value)
        tick()
    }

    /// Adopts a new source report. Small deviations from the extrapolated
    /// position (≤ 2 s) are treated as polling jitter and ignored so the
    /// display doesn't stutter; anything larger is a seek and snaps.
    func apply(_ state: NowPlayingState?) {
        defer { tick() }
        guard let new = state else {
            anchor = nil
            return
        }
        if let current = anchor,
           current.isSameTrack(as: new),
           current.isPlaying == new.isPlaying,
           new.isPlaying {
            let expected = Self.extrapolatedPositionMs(anchor: current, at: new.capturedAt)
            if abs(expected - new.positionMs) <= Self.seekThresholdMs {
                return // within jitter tolerance — keep the smoother existing anchor
            }
        }
        anchor = new // new track, play/pause flip, or a real seek: snap
    }

    func startTicking() {
        timer = Timer.publish(every: Self.tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        tick()
    }

    func stopTicking() {
        timer = nil
        liveActivityBoundaryTask?.cancel()
        liveActivityBoundaryTask = nil
    }

    func tick() {
        liveActivityBoundaryTask?.cancel()
        liveActivityBoundaryTask = nil
        guard let anchor else {
            positionSubject.send(nil)
            liveActivityPositionSubject.send(nil)
            return
        }
        let pos = Self.extrapolatedPositionMs(anchor: anchor, at: now())
        positionSubject.send(Self.position(
            atMs: pos, lines: lines,
            durationMs: anchor.durationMs, isPlaying: anchor.isPlaying,
            displayOptions: displayOptions, offsetMs: offsetMs
        ))
        liveActivityPositionSubject.send(Self.position(
            atMs: pos, lines: lines,
            durationMs: anchor.durationMs, isPlaying: anchor.isPlaying,
            displayOptions: displayOptions, offsetMs: offsetMs,
            lineLookaheadMs: liveActivityLineLeadMs
        ))
        // Fire at the transition boundary itself, rather than waiting up to
        // another 250 ms for the regular playback sample.
        if timer != nil, anchor.isPlaying,
           let deadline = Self.nextLiveActivityRefreshMs(
               at: max(0, pos - offsetMs), lines: lines, leadMs: liveActivityLineLeadMs
           ) {
            let delayMs = max(1, deadline - max(0, pos - offsetMs))
            liveActivityBoundaryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    // MARK: - Pure helpers

    static func extrapolatedPositionMs(anchor: NowPlayingState, at date: Date) -> Int {
        guard anchor.isPlaying else { return anchor.positionMs }
        let elapsedMs = Int((date.timeIntervalSince(anchor.capturedAt) * 1000).rounded())
        let pos = max(0, anchor.positionMs + elapsedMs)
        if let duration = anchor.durationMs {
            return min(pos, duration)
        }
        return pos
    }

    /// Index of the last line with timestamp ≤ position (binary search);
    /// nil before the first line or when there are no lines.
    static func lineIndex(forPositionMs pos: Int, in lines: [LyricsLine]) -> Int? {
        guard let first = lines.first, pos >= first.startTimeMs else { return nil }
        var lo = 0
        var hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].startTimeMs <= pos {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    static func position(
        atMs pos: Int,
        lines: [LyricsLine],
        durationMs: Int?,
        isPlaying: Bool,
        displayOptions: LyricsDisplayOptions = LyricsDisplayOptions(),
        offsetMs: Int = 0,
        lineLookaheadMs: Int = 0
    ) -> LyricsPosition {
        let lyricPositionMs = max(0, pos - offsetMs)
        let actualIndex = lineIndex(forPositionMs: lyricPositionMs, in: lines)
        let lookaheadMs = isPlaying ? max(0, lineLookaheadMs) : 0
        var index = actualIndex
        let upcoming = actualIndex.map { $0 + 1 } ?? 0
        // Only the immediately upcoming line can advance. A long effect must
        // not skip several short lyric lines in one lookahead window.
        if lookaheadMs > 0, lines.indices.contains(upcoming),
           lines[upcoming].startTimeMs <= lyricPositionMs + lookaheadMs {
            index = upcoming
        }
        let currentLine = index.map { LyricsTextRenderer.primary(for: lines[$0], options: displayOptions) }
        let currentSecondaryLine = index.flatMap {
            LyricsTextRenderer.secondary(for: lines[$0], options: displayOptions)
        }
        let currentWords = index.flatMap { lines[$0].words }.map { words in
            words.map { word in
                LyricWordTiming(
                    startTimeMs: word.startTimeMs,
                    endTimeMs: word.endTimeMs,
                    original: ChineseTextConverter.convert(
                        word.original,
                        using: displayOptions.chineseConversion
                    )
                )
            }
        }
        let currentWordIndex = currentWords?.lastIndex {
            lyricPositionMs >= $0.startTimeMs
        } ?? (lookaheadMs > 0 && currentWords?.isEmpty == false ? 0 : nil)
        let nextIndex: Int?
        if let index {
            nextIndex = index + 1 < lines.count ? index + 1 : nil
        } else {
            nextIndex = lines.isEmpty ? nil : 0
        }
        let nextLine = nextIndex.map { LyricsTextRenderer.primary(for: lines[$0], options: displayOptions) }
        let nextSecondaryLine = nextIndex.flatMap {
            LyricsTextRenderer.secondary(for: lines[$0], options: displayOptions)
        }

        var lineProgress = 0.0
        var currentLineRemainingMs: Int?
        if let index {
            let start = lines[index].startTimeMs
            let end = lines[index].endTimeMs
                ?? (index + 1 < lines.count ? lines[index + 1].startTimeMs : nil)
                ?? durationMs
                ?? (start + 5000)
            currentLineRemainingMs = max(0, end - lyricPositionMs)
            if end > start {
                lineProgress = min(1, max(0, Double(lyricPositionMs - start) / Double(end - start)))
            }
        }
        let trackProgress = durationMs.flatMap { dur in
            dur > 0 ? min(1, max(0, Double(pos) / Double(dur))) : nil
        } ?? 0

        return LyricsPosition(
            positionMs: pos, lyricPositionMs: lyricPositionMs, lineIndex: index,
            currentLine: currentLine, currentSecondaryLine: currentSecondaryLine,
            currentWords: currentWords, currentWordIndex: currentWordIndex,
            nextLine: nextLine, nextSecondaryLine: nextSecondaryLine,
            currentLineRemainingMs: currentLineRemainingMs,
            lineProgress: lineProgress, trackProgress: trackProgress,
            isPlaying: isPlaying
        )
    }

    /// Once the next line has been prepared, refresh at its real timestamp too
    /// so the following line can be scheduled without delaying its boundary.
    static func nextLiveActivityRefreshMs(at positionMs: Int, lines: [LyricsLine],
                                         leadMs: Int) -> Int? {
        let current = lineIndex(forPositionMs: positionMs, in: lines)
        let upcoming = current.map { $0 + 1 } ?? 0
        guard lines.indices.contains(upcoming) else { return nil }
        let start = lines[upcoming].startTimeMs
        let trigger = start - max(0, leadMs)
        return trigger > positionMs ? trigger : start
    }
}
