import Foundation
import Combine

struct LyricsPosition: Equatable {
    let positionMs: Int
    let lyricPositionMs: Int
    let lineIndex: Int?
    let currentLine: String?
    let currentSecondaryLine: String?
    let currentWords: [LyricWordTiming]?
    let nextLine: String?
    let nextSecondaryLine: String?
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
    static let tickInterval: TimeInterval = 0.5

    var now: () -> Date
    private(set) var anchor: NowPlayingState?
    private(set) var lines: [LyricsLine] = []
    private(set) var displayOptions = LyricsDisplayOptions()
    private(set) var offsetMs = 0
    let positionSubject = CurrentValueSubject<LyricsPosition?, Never>(nil)
    private var timer: AnyCancellable?

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
    }

    func stopTicking() {
        timer = nil
    }

    func tick() {
        guard let anchor else {
            positionSubject.send(nil)
            return
        }
        let pos = Self.extrapolatedPositionMs(anchor: anchor, at: now())
        positionSubject.send(Self.position(
            atMs: pos, lines: lines,
            durationMs: anchor.durationMs, isPlaying: anchor.isPlaying,
            displayOptions: displayOptions, offsetMs: offsetMs
        ))
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
        offsetMs: Int = 0
    ) -> LyricsPosition {
        let lyricPositionMs = max(0, pos - offsetMs)
        let index = lineIndex(forPositionMs: lyricPositionMs, in: lines)
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
        if let index {
            let start = lines[index].startTimeMs
            let end = lines[index].endTimeMs
                ?? (index + 1 < lines.count ? lines[index + 1].startTimeMs : nil)
                ?? durationMs
                ?? (start + 5000)
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
            currentWords: currentWords,
            nextLine: nextLine, nextSecondaryLine: nextSecondaryLine,
            lineProgress: lineProgress, trackProgress: trackProgress,
            isPlaying: isPlaying
        )
    }
}
