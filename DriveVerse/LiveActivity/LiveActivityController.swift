import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import os

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
    /// Rapid line changes are coalesced (never dropped) to one update per
    /// this interval; the newest line always lands, at worst this late.
    /// Track changes and play/pause flips always send immediately.
    static let minLineUpdateInterval: TimeInterval = 1.5

    private static let log = Logger(subsystem: "io.github.mels.driveverse", category: "activity")

    private var activity: Activity<LyricsAttributes>?
    private var policy = LiveActivityUpdatePolicy()
    private var throttle = LiveActivityUpdateThrottle(minInterval: LiveActivityController.minLineUpdateInterval)
    private var endTask: Task<Void, Never>?
    private var stateWatcher: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var pendingContent: LyricsAttributes.ContentState?
    private var lastSentTrackKey: String?
    private var lastSentIsPlaying: Bool?
    private var lastSentPositionMs: Int?
    private var lastSentAt: Date?

    /// While Drive Mode is on the session must survive arbitrary pauses:
    /// hold the activity (pause glyph) instead of ending it after the grace
    /// period, because a fresh start would need the foreground.
    var holdWhilePaused = false

    /// Display preferences can change without a track or line change.
    /// Reset deduplication so the newly rendered text reaches ActivityKit.
    func forceNextUpdate() {
        policy.reset()
        lastSentTrackKey = nil
        lastSentIsPlaying = nil
        lastSentPositionMs = nil
        lastSentAt = nil
        cancelPendingUpdate()
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
        let seekedWithinLine: Bool
        if let sentPosition = lastSentPositionMs, let sentAt = lastSentAt,
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
            isPlaying: state.isPlaying
        )
        guard seekedWithinLine || policyWantsUpdate else { return }

        let critical = key != lastSentTrackKey
            || state.isPlaying != lastSentIsPlaying
            || seekedWithinLine
        lastSentTrackKey = key
        lastSentIsPlaying = state.isPlaying
        lastSentPositionMs = position?.positionMs ?? state.positionMs
        lastSentAt = now
        let content = Self.content(state: state, position: position)

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

    /// Requests the session's activity. Reached two ways: from sync() once a
    /// lyric-bearing track plays in the foreground, or from the Start Drive
    /// Mode intent — the one background context iOS grants Activity.request
    /// to. The intent path may run before any music plays; the placeholder
    /// content matters because a background app can only *update* from then on.
    func beginSession(state: NowPlayingState?, position: LyricsPosition?) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = state.map { Self.content(state: $0, position: position) }
            ?? LyricsAttributes.ContentState(
                title: "DriveVerse", artist: "",
                artworkData: nil,
                currentLine: String(localized: "♪ Waiting for music…"),
                secondaryLine: "", nextLine: "",
                currentWords: [], trackPositionMs: 0, lyricPositionMs: 0,
                playbackReferenceDate: Date(), durationMs: nil,
                progress: 0, isPlaying: false
            )
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
                lastSentIsPlaying = state.isPlaying
                lastSentPositionMs = position?.positionMs ?? state.positionMs
                lastSentAt = Date()
                policy.seed(
                    trackKey: Self.key(for: state),
                    lineIndex: position?.lineIndex,
                    isPlaying: state.isPlaying
                )
            } else {
                lastSentTrackKey = nil
                lastSentIsPlaying = nil
                lastSentPositionMs = nil
                lastSentAt = nil
                policy.reset()
            }
        } catch {
            Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
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
                    self.lastSentPositionMs = nil
                    self.lastSentAt = nil
                    self.cancelPendingUpdate()
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
        guard let activity else { return }
        self.activity = nil
        policy.reset()
        lastSentPositionMs = nil
        lastSentAt = nil
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

    private static func content(state: NowPlayingState, position: LyricsPosition?) -> LyricsAttributes.ContentState {
        LyricsAttributes.ContentState(
            title: String(state.title.prefix(64)),
            artist: String(state.artist.prefix(64)),
            artworkData: state.artworkData,
            currentLine: String((position?.currentLine ?? "♪ \(state.title)").prefix(120)),
            secondaryLine: String((position?.currentSecondaryLine ?? "").prefix(100)),
            nextLine: String((position?.nextLine ?? "").prefix(100)),
            currentWords: activityWords(position?.currentWords),
            trackPositionMs: position?.positionMs ?? state.positionMs,
            lyricPositionMs: position?.lyricPositionMs ?? state.positionMs,
            playbackReferenceDate: Date(),
            durationMs: state.durationMs,
            progress: position?.trackProgress ?? 0,
            isPlaying: state.isPlaying
        )
    }

    private static func activityWords(_ words: [LyricWordTiming]?) -> [LyricsAttributes.Word] {
        guard let words,
              words.count <= 24,
              words.allSatisfy({ $0.original.count <= 16 }),
              words.reduce(0, { $0 + $1.original.utf8.count }) <= 256 else {
            return []
        }
        return words.map {
            LyricsAttributes.Word(
                text: $0.original,
                startTimeMs: $0.startTimeMs,
                endTimeMs: $0.endTimeMs
            )
        }
    }
}
#endif
