import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import os
import UIKit

/// Owns the lyrics Live Activity lifecycle.
///
/// One activity spans the whole listening session: iOS refuses
/// Activity.request from a backgrounded app, so the original
/// end-and-restart-per-track design lost the tile on every backgrounded song
/// change. Track changes are now plain updates (allowed from the background);
/// the activity ends only after playback has stopped for the grace period.
/// Lyric-less tracks keep the tile alive showing "♪ title" so a later track
/// with lyrics doesn't need a (background-impossible) fresh start.
/// On iOS 26 the lock-screen presentation is mirrored onto CarPlay for free.
@MainActor
final class LiveActivityController {
    static let endDelay: TimeInterval = 30
    /// Rapid line/word changes are coalesced (never dropped) to one update per
    /// this interval; the newest lyric state always lands, at worst this late.
    /// Track changes and play/pause flips always send immediately.
    static let minUpdateInterval: TimeInterval = 0.20

    private static let log = Logger(subsystem: "io.github.mels.driveverse", category: "activity")

    private var activity: Activity<LyricsAttributes>?
    private var policy = LiveActivityUpdatePolicy()
    private var throttle = LiveActivityUpdateThrottle(minInterval: LiveActivityController.minUpdateInterval)
    private var endTask: Task<Void, Never>?
    private var stateWatcher: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var lineMarqueeTask: Task<Void, Never>?
    private var pendingContent: LyricsAttributes.ContentState?
    private var latestContent: LyricsAttributes.ContentState?
    private var lastSentTrackKey: String?
    private var lastSentLineIndex: Int?
    private var lastSentIsPlaying: Bool?
    private var lastSentPositionMs: Int?
    private var lastSentAt: Date?
    private var lineMarqueeAtEnd = false
    private var lineMarqueeDelay: TimeInterval = 0.5
    private var lineMarqueeDuration: TimeInterval = 1.8

    /// While Drive Mode is on the session must survive arbitrary pauses:
    /// hold the activity (pause glyph) instead of ending it after the grace
    /// period, because a fresh start would need the foreground.
    var holdWhilePaused = false

    /// When disabled, both update deduplication and rendered content ignore
    /// the current word. All Live Activity families then update per line.
    var wordUpdatesEnabled = true {
        didSet {
            guard wordUpdatesEnabled != oldValue else { return }
            forceNextUpdate()
        }
    }

    /// Display preferences can change without a track or line change.
    /// Reset deduplication so the newly rendered text reaches ActivityKit.
    func forceNextUpdate() {
        policy.reset()
        lastSentTrackKey = nil
        lastSentLineIndex = nil
        lastSentIsPlaying = nil
        lastSentPositionMs = nil
        lastSentAt = nil
        cancelPendingUpdate()
        cancelLineMarquee()
        lineMarqueeAtEnd = false
        lineMarqueeDelay = 0.5
        lineMarqueeDuration = 1.8
        latestContent = nil
        throttle = LiveActivityUpdateThrottle(minInterval: Self.minUpdateInterval)
    }

    init() {
        // Clean up activities orphaned by a previous app termination.
        Task {
            for stale in Activity<LyricsAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Single entry point, called from AppModel on every state/position change.
    func sync(state: NowPlayingState?, position: LyricsPosition?, hasSyncedLyrics: Bool) {
        guard let state else {
            if holdWhilePaused { cancelScheduledEnd() } else { scheduleEnd() }
            return
        }

        guard let activity else {
            // First start needs a playing track with synced lyrics and a
            // foregrounded app — the request throws in the background and is
            // simply retried on a later sync (heals on foreground resync).
            // The Start Drive Mode intent bypasses this via beginSession.
            if state.isPlaying, hasSyncedLyrics {
                beginSession(state: state, position: position)
            }
            return
        }

        if state.isPlaying || holdWhilePaused {
            cancelScheduledEnd()
        } else {
            scheduleEnd()
        }

        let key = Self.key(for: state)
        let now = Date()
        let trackChanged = key != lastSentTrackKey
        let lineChanged = key == lastSentTrackKey
            && position?.lineIndex != lastSentLineIndex
        let startsLineMarquee = trackChanged || lineChanged
        let needsLineMarquee = startsLineMarquee
            && Self.compactLineNeedsMarquee(position?.currentLine ?? "♪ \(state.title)")
        if startsLineMarquee {
            cancelLineMarquee()
            lineMarqueeAtEnd = false
            let timing = Self.marqueeTiming(
                remainingMs: position?.currentLineRemainingMs
            )
            lineMarqueeDelay = timing.delay
            lineMarqueeDuration = timing.duration
        }
        let seekedWithinLine: Bool
        if wordUpdatesEnabled,
           let sentPosition = lastSentPositionMs, let sentAt = lastSentAt,
           key == lastSentTrackKey, state.isPlaying == lastSentIsPlaying,
           let position {
            let elapsed = state.isPlaying ? Int(now.timeIntervalSince(sentAt) * 1_000) : 0
            seekedWithinLine = abs(position.positionMs - (sentPosition + elapsed))
                > SyncEngine.seekThresholdMs
        } else {
            seekedWithinLine = false
        }
        let policyWantsUpdate = policy.shouldUpdate(
            trackKey: key,
            lineIndex: position?.lineIndex,
            wordIndex: wordUpdatesEnabled ? position?.currentWordIndex : nil,
            isPlaying: state.isPlaying
        )
        guard seekedWithinLine || policyWantsUpdate else { return }

        let critical = trackChanged
            || state.isPlaying != lastSentIsPlaying
            || lineChanged
            || seekedWithinLine
        lastSentTrackKey = key
        lastSentLineIndex = position?.lineIndex
        lastSentIsPlaying = state.isPlaying
        lastSentPositionMs = position?.positionMs ?? state.positionMs
        lastSentAt = now
        let content = Self.content(
            state: state,
            position: position,
            wordUpdatesEnabled: wordUpdatesEnabled,
            lineMarqueeAtEnd: lineMarqueeAtEnd,
            lineMarqueeDuration: lineMarqueeDuration
        )
        latestContent = content

        switch throttle.decide(critical: critical, now: now) {
        case .sendNow:
            cancelPendingUpdate() // superseded by newer content
            Task {
                await activity.update(ActivityContent(state: content, staleDate: nil))
            }
        case .coalesce(let fireIn):
            pendingContent = content
            armPendingUpdate(after: fireIn, on: activity)
        }
        if needsLineMarquee {
            scheduleLineMarqueeEnd(
                expectedTrackKey: key,
                expectedLineIndex: position?.lineIndex,
                delay: lineMarqueeDelay,
                on: activity
            )
        }
    }

    /// Trailing edge of the throttle: deliver the newest coalesced content
    /// once the spacing interval elapses, so no line change is ever lost.
    private func armPendingUpdate(after delay: TimeInterval, on activity: Activity<LyricsAttributes>) {
        guard pendingTask == nil else { return } // armed — content already replaced
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let content = self.pendingContent else { return }
            self.pendingContent = nil
            self.pendingTask = nil
            self.throttle.noteSent(now: Date())
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    private func cancelPendingUpdate() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingContent = nil
    }

    /// Widget-local state changes are flattened before a Live Activity view
    /// is rendered. Submit a second compact-only phase after the line-start
    /// state so WidgetKit has two ContentState values to interpolate.
    private func scheduleLineMarqueeEnd(
        expectedTrackKey: String,
        expectedLineIndex: Int?,
        delay: TimeInterval,
        on activity: Activity<LyricsAttributes>
    ) {
        lineMarqueeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.activity?.id == activity.id,
                  self.lastSentTrackKey == expectedTrackKey,
                  self.lastSentLineIndex == expectedLineIndex,
                  var content = self.latestContent else { return }
            self.lineMarqueeAtEnd = true
            content.lineMarqueeAtEnd = true
            self.latestContent = content
            self.throttle.noteSent(now: Date())
            await activity.update(ActivityContent(state: content, staleDate: nil))
            self.lineMarqueeTask = nil
        }
    }

    private func cancelLineMarquee() {
        lineMarqueeTask?.cancel()
        lineMarqueeTask = nil
    }

    /// Requests the session's activity. Reached two ways: from sync() once a
    /// lyric-bearing track plays in the foreground, or from the Start Drive
    /// Mode intent — the one background context iOS grants Activity.request
    /// to. The intent path may run before any music plays; the placeholder
    /// content matters because a background app can only *update* from then on.
    func beginSession(state: NowPlayingState?, position: LyricsPosition?) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        lineMarqueeAtEnd = false
        let timing = Self.marqueeTiming(remainingMs: position?.currentLineRemainingMs)
        lineMarqueeDelay = timing.delay
        lineMarqueeDuration = timing.duration
        let content = state.map {
            Self.content(
                state: $0,
                position: position,
                wordUpdatesEnabled: wordUpdatesEnabled,
                lineMarqueeAtEnd: false,
                lineMarqueeDuration: lineMarqueeDuration
            )
        }
            ?? LyricsAttributes.ContentState(
                title: "DriveVerse", artist: "",
                artworkData: nil,
                secondaryLine: "", nextLine: "",
                completedText: "", activeText: String(localized: "♪ Waiting for music…"),
                remainingText: "",
                lineIndex: nil, usesWordTiming: false, lineMarqueeAtEnd: false,
                lineMarqueeDurationMs: 0,
                isPlaying: false
            )
        latestContent = content
        do {
            let requested = try Activity.request(
                attributes: LyricsAttributes(),
                content: ActivityContent(state: content, staleDate: nil)
            )
            activity = requested
            watch(requested)
            throttle.noteSent(now: Date())
            if let state {
                lastSentTrackKey = Self.key(for: state)
                lastSentLineIndex = position?.lineIndex
                lastSentIsPlaying = state.isPlaying
                lastSentPositionMs = position?.positionMs ?? state.positionMs
                lastSentAt = Date()
                policy.seed(
                    trackKey: Self.key(for: state),
                    lineIndex: position?.lineIndex,
                    wordIndex: wordUpdatesEnabled ? position?.currentWordIndex : nil,
                    isPlaying: state.isPlaying
                )
                if Self.compactLineNeedsMarquee(position?.currentLine ?? "♪ \(state.title)") {
                    scheduleLineMarqueeEnd(
                        expectedTrackKey: Self.key(for: state),
                        expectedLineIndex: position?.lineIndex,
                        delay: lineMarqueeDelay,
                        on: requested
                    )
                }
            } else {
                lastSentTrackKey = nil
                lastSentLineIndex = nil
                lastSentIsPlaying = nil
                lastSentPositionMs = nil
                lastSentAt = nil
                policy.reset()
            }
        } catch {
            Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
            latestContent = nil
        }
    }

    /// The system can end or dismiss the activity without asking us (user
    /// swipe, system policy). Without this watcher we'd keep "updating" a
    /// corpse while believing everything is fine.
    private func watch(_ requested: Activity<LyricsAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in requested.activityStateUpdates {
                guard let self, state == .ended || state == .dismissed else { continue }
                if self.activity?.id == requested.id {
                    self.activity = nil
                    self.policy.reset()
                    self.lastSentTrackKey = nil
                    self.lastSentLineIndex = nil
                    self.lastSentPositionMs = nil
                    self.lastSentAt = nil
                    self.lineMarqueeAtEnd = false
                    self.latestContent = nil
                    self.cancelPendingUpdate()
                    self.cancelLineMarquee()
                    Self.log.warning("activity ended outside the app — background restart impossible; reopen the app or rerun the CarPlay automation")
                }
            }
        }
    }

    func endNow() async {
        endTask?.cancel()
        endTask = nil
        stateWatcher?.cancel()
        stateWatcher = nil
        cancelPendingUpdate()
        cancelLineMarquee()
        guard let activity else { return }
        self.activity = nil
        policy.reset()
        lastSentTrackKey = nil
        lastSentLineIndex = nil
        lastSentPositionMs = nil
        lastSentAt = nil
        lineMarqueeAtEnd = false
        latestContent = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Internals

    private func scheduleEnd() {
        guard endTask == nil, activity != nil else { return }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.endDelay))
            guard !Task.isCancelled else { return }
            await self?.endNow()
        }
    }

    private func cancelScheduledEnd() {
        endTask?.cancel()
        endTask = nil
    }

    private static func key(for state: NowPlayingState) -> String {
        "\(state.title)|\(state.artist)|\(state.album ?? "")|art:\(state.artworkData?.hashValue ?? 0)"
    }

    /// Leave a short readable hold at the line start, then fit the entire
    /// pass before the next lyric replaces it. Long lines retain the tested
    /// 1.8 s cap; short lines proportionally compress both phases.
    private static func marqueeTiming(
        remainingMs: Int?
    ) -> (delay: TimeInterval, duration: TimeInterval) {
        let remaining = Double(max(0, remainingMs ?? 2_300)) / 1_000
        // Reserve 250 ms for ActivityKit delivery/render latency so the
        // visual pass normally settles before the next line update arrives.
        let available = max(0.20, remaining - 0.25)
        let delay = min(0.5, max(0.08, available * 0.20))
        let duration = min(1.8, max(0.12, available - delay))
        return (delay, duration)
    }

    /// Device testing shows the compact trailing region holds roughly twelve
    /// Latin characters or six CJK characters. Measure with the same font and
    /// 88-point maximum as the widget so only actual overflow gets phase two.
    private static func compactLineNeedsMarquee(_ line: String) -> Bool {
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold)
            ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        let text = String(line.prefix(100)) as NSString
        return ceil(text.size(withAttributes: [.font: font]).width) > 88
    }

    private static func content(
        state: NowPlayingState,
        position: LyricsPosition?,
        wordUpdatesEnabled: Bool,
        lineMarqueeAtEnd: Bool,
        lineMarqueeDuration: TimeInterval
    ) -> LyricsAttributes.ContentState {
        let line = String((position?.currentLine ?? "♪ \(state.title)").prefix(100))
        let segments = wordSegments(
            position: position,
            fallback: line,
            enabled: wordUpdatesEnabled
        )
        return LyricsAttributes.ContentState(
            title: String(state.title.prefix(48)),
            artist: String(state.artist.prefix(48)),
            artworkData: state.artworkData,
            secondaryLine: String((position?.currentSecondaryLine ?? "").prefix(72)),
            nextLine: String((position?.nextLine ?? "").prefix(72)),
            completedText: segments.completed,
            activeText: segments.active,
            remainingText: segments.remaining,
            lineIndex: position?.lineIndex,
            usesWordTiming: segments.usesWordTiming,
            lineMarqueeAtEnd: lineMarqueeAtEnd,
            lineMarqueeDurationMs: Int((lineMarqueeDuration * 1_000).rounded()),
            isPlaying: state.isPlaying
        )
    }

    private static func wordSegments(
        position: LyricsPosition?,
        fallback: String,
        enabled: Bool
    ) -> (completed: String, active: String, remaining: String, usesWordTiming: Bool) {
        guard enabled else { return (fallback, "", "", false) }
        guard let words = position?.currentWords, !words.isEmpty,
              let index = position?.currentWordIndex, words.indices.contains(index) else {
            return ("", fallback, "", false)
        }
        guard words.reduce(0, { $0 + $1.original.count }) <= 100 else {
            return ("", fallback, "", false)
        }
        let completed = words[..<index].map(\.original).joined()
        let active = words[index].original
        let remaining = words[(index + 1)...].map(\.original).joined()
        return (completed, active, remaining, true)
    }
}
#endif
