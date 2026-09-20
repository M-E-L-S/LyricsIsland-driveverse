import Foundation
import Combine
import os
#if canImport(ActivityKit)
import ActivityKit
#endif

enum LyricsDisplayState: Equatable {
    case idle       // nothing playing yet
    case loading
    case synced(LyricsDocument)
    case plain(LyricsDocument)
    case instrumental
    case notFound
    case failed
}

/// Central wiring: Apple Music → sync engine → lyrics → UI and Live Activity.
@MainActor
final class AppModel: ObservableObject {
    /// Single shared instance: the SwiftUI scene and the Drive Mode App
    /// Intents (which can launch the process in the background) must drive
    /// the same pipeline.
    static let shared = AppModel()

    private static let log = Logger(subsystem: "io.github.mels.driveverse", category: "pipeline")
    private static let displayModeKey = "lyricsDisplayMode"
    private static let chineseConversionKey = "lyricsChineseConversion"
    private static let timingOffsetKey = "lyricsTimingOffsetMs"
    private static let lyricsEnabledKey = "lyricsEnabled"
    private static let liveActivityWordUpdatesKey = "liveActivityWordUpdatesEnabled"

    // MARK: UI state

    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var lyricsState: LyricsDisplayState = .idle
    @Published private(set) var currentLyricsSource: LyricsSource?
    @Published private(set) var lyricsCandidates: [LyricsCandidateChoice] = []
    @Published private(set) var selectedLyricsCandidateID: String?
    @Published private(set) var isUsingManualLyrics = false
    @Published private(set) var position: LyricsPosition?
    @Published private(set) var appleMusicAuth: MediaAuthStatus = .unknown
    @Published var errorMessage: String?
    @Published var lyricsEnabled: Bool {
        didSet {
            defaults.set(lyricsEnabled, forKey: Self.lyricsEnabledKey)
            if lyricsEnabled {
#if os(iOS)
                liveActivity.holdWhilePaused = driveMode
#endif
                currentSignature = nil
                if let state = nowPlaying { fetchLyrics(for: state) }
                syncLiveActivity()
            } else {
                disableLyrics()
            }
        }
    }
    @Published var liveActivityWordUpdatesEnabled: Bool {
        didSet {
            defaults.set(liveActivityWordUpdatesEnabled, forKey: Self.liveActivityWordUpdatesKey)
#if os(iOS)
            liveActivity.wordUpdatesEnabled = liveActivityWordUpdatesEnabled
            syncLiveActivity()
#endif
        }
    }
    @Published var lyricsDisplayMode: LyricsDisplayMode {
        didSet {
            defaults.set(lyricsDisplayMode.rawValue, forKey: Self.displayModeKey)
            refreshLyricsPresentation()
            if LyricsSecondaryRequirement(displayMode: oldValue)
                != LyricsSecondaryRequirement(displayMode: lyricsDisplayMode),
               let state = nowPlaying {
                fetchLyrics(for: state)
            }
        }
    }
    @Published var chineseConversion: ChineseConversion {
        didSet {
            defaults.set(chineseConversion.rawValue, forKey: Self.chineseConversionKey)
            refreshLyricsPresentation()
        }
    }
    @Published var lyricsTimingOffsetMs: Int {
        didSet {
            defaults.set(lyricsTimingOffsetMs, forKey: Self.timingOffsetKey)
            syncEngine.setOffsetMs(lyricsTimingOffsetMs)
        }
    }
    @Published var driveMode = false {
        didSet {
#if os(iOS)
            liveActivity.holdWhilePaused = driveMode && lyricsEnabled
#if canImport(ActivityKit)
            // Surface the system's frequent-update preference. ActivityKit
            // still controls rendering cadence, and Apple documents this
            // preference primarily for ActivityKit push notifications.
            if driveMode, lyricsEnabled, !ActivityAuthorizationInfo().frequentPushesEnabled {
                errorMessage = String(localized: "For smooth lyrics, turn on Settings → DriveVerse → Live Activities → More Frequent Updates.")
            }
#endif
#endif
            syncLiveActivity()
        }
    }

    // MARK: Pipeline

#if os(iOS)
    private let appleSource: AppleMusicSource
    private let liveActivity = LiveActivityController()
    private let backgroundKeeper = BackgroundKeeper()
#endif
    private let syncEngine = SyncEngine()
    private let lyricsService = LyricsService()
    private let defaults: UserDefaults

    private var cancellables: Set<AnyCancellable> = []
    private var lyricsTask: Task<Void, Never>?
    private var currentSignature: String?
    private var started = false

    var lyricsDisplayOptions: LyricsDisplayOptions {
        LyricsDisplayOptions(
            mode: lyricsDisplayMode,
            chineseConversion: chineseConversion
        )
    }

    var playbackAnchor: NowPlayingState? { syncEngine.anchor }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lyricsEnabled = defaults.object(forKey: Self.lyricsEnabledKey) as? Bool ?? true
        liveActivityWordUpdatesEnabled = defaults.object(
            forKey: Self.liveActivityWordUpdatesKey
        ) as? Bool ?? true
        lyricsDisplayMode = defaults.string(forKey: Self.displayModeKey)
            .flatMap(LyricsDisplayMode.init(rawValue:)) ?? .originalAndTranslation
        chineseConversion = defaults.string(forKey: Self.chineseConversionKey)
            .flatMap(ChineseConversion.init(rawValue:)) ?? .preserve
        lyricsTimingOffsetMs = min(5_000, max(-5_000, defaults.integer(forKey: Self.timingOffsetKey)))

        let applePublisher: AnyPublisher<NowPlayingState?, Never>
#if os(iOS)
        let apple = AppleMusicSource()
        appleSource = apple
        applePublisher = apple.statePublisher
#else
        applePublisher = Just<NowPlayingState?>(nil).eraseToAnyPublisher()
#endif

        syncEngine.setDisplayOptions(lyricsDisplayOptions)
        syncEngine.setOffsetMs(lyricsTimingOffsetMs)
        wire(nowPlayingPublisher: applePublisher)

#if os(iOS)
        liveActivity.wordUpdatesEnabled = liveActivityWordUpdatesEnabled
        backgroundKeeper.onIssue = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
                self?.driveMode = false
            }
        }
#endif
    }

    func start() {
        guard !started else { return }
        started = true
#if os(iOS)
        appleSource.start()
#endif
        syncEngine.startTicking()
    }

    /// Called when the scene returns to .active: any background stretch may
    /// have left the lyric index stale (missed notifications, old anchors),
    /// so force a fresh Apple Music read; the sync engine's seek
    /// detection snaps the line immediately.
    func foregroundResync() {
        guard started else { return }
#if os(iOS)
        appleSource.refresh()
#endif
    }

    /// Entry point for the Start Drive Mode intent. May run with the app
    /// launched straight into the background, where the LiveActivityIntent
    /// grant is the only legal way to request an activity — so one is started
    /// immediately (a placeholder until music plays); everything after that
    /// is a plain background update.
    func startDriveSession() {
#if os(iOS)
        start()
        driveMode = true
        if lyricsEnabled {
            liveActivity.beginSession(state: nowPlaying, position: position)
        }
        foregroundResync()
#endif
    }

    /// Entry point for the Stop Drive Mode intent (leaving the car): stop
    /// holding the session and take the tile down right away.
    func stopDriveSession() {
        driveMode = false
#if os(iOS)
        Task { await liveActivity.endNow() }
#endif
    }

    // MARK: Actions

    func togglePlayback() {
#if os(iOS)
        appleSource.togglePlayback()
#endif
    }

    func skipToPreviousItem() {
#if os(iOS)
        appleSource.skipToPreviousItem()
#endif
    }

    func skipToNextItem() {
#if os(iOS)
        appleSource.skipToNextItem()
#endif
    }

    func seek(toFraction fraction: Double) {
#if os(iOS)
        appleSource.seek(toFraction: fraction)
#endif
    }

    func seek(bySeconds offset: Double) {
#if os(iOS)
        appleSource.seek(bySeconds: offset)
#endif
    }

    func retryLyrics() {
        guard lyricsEnabled, let state = nowPlaying else { return }
        lyricsService.useAutomaticSelection(for: state, displayMode: lyricsDisplayMode)
        currentSignature = LyricsMatcher.signature(
            title: state.title,
            artist: state.artist,
            durationMs: state.durationMs,
            album: state.album
        )
        fetchLyrics(for: state, forceRefresh: true)
    }

    func selectLyricsCandidate(_ choice: LyricsCandidateChoice) {
        guard lyricsEnabled, let state = nowPlaying else { return }
        lyricsService.select(choice, for: state, displayMode: lyricsDisplayMode)
        selectedLyricsCandidateID = choice.id
        isUsingManualLyrics = true
        applyLyricsContent(choice.content)
    }

    func useAutomaticLyrics() {
        guard lyricsEnabled, let state = nowPlaying else { return }
        lyricsService.useAutomaticSelection(for: state, displayMode: lyricsDisplayMode)
        fetchLyrics(for: state)
    }

    func clearLyricsCache() {
        lyricsService.clearCache()
        lyricsCandidates = []
        selectedLyricsCandidateID = nil
        isUsingManualLyrics = false
    }

    func resetLyricsTimingOffset() {
        lyricsTimingOffsetMs = 0
    }

    // MARK: Wiring

    private func wire(nowPlayingPublisher: AnyPublisher<NowPlayingState?, Never>) {
        nowPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)

        syncEngine.positionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.position = position
                self?.syncLiveActivity()
            }
            .store(in: &cancellables)

#if os(iOS)
        appleSource.authStatusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.appleMusicAuth = $0 }
            .store(in: &cancellables)
#endif
    }

    private func handle(_ state: NowPlayingState?) {
        nowPlaying = state
        syncEngine.apply(state)

        guard let state else {
            currentSignature = nil
            lyricsTask?.cancel()
            syncEngine.setLyrics([])
            lyricsState = .idle
            currentLyricsSource = nil
            lyricsCandidates = []
            selectedLyricsCandidateID = nil
            isUsingManualLyrics = false
            return
        }

        guard lyricsEnabled else {
            currentSignature = nil
            return
        }

        let signature = LyricsMatcher.signature(
            title: state.title,
            artist: state.artist,
            durationMs: state.durationMs,
            album: state.album
        )
        if signature != currentSignature {
            currentSignature = signature
            fetchLyrics(for: state)
        }
        syncLiveActivity()
    }

    private func refreshLyricsPresentation() {
#if os(iOS)
        liveActivity.forceNextUpdate()
#endif
        syncEngine.setDisplayOptions(lyricsDisplayOptions)
    }

    /// The controller's update policy dedupes the 250 ms ticks — depending on
    /// the user's setting, only active word/line changes or line changes reach
    /// ActivityKit. Track and playback-state changes are always immediate.
    private func syncLiveActivity() {
#if os(iOS)
        guard lyricsEnabled else {
            updateKeepAlive()
            return
        }
        var hasSyncedLyrics = false
        if case .synced = lyricsState { hasSyncedLyrics = true }
        liveActivity.sync(state: nowPlaying, position: position, hasSyncedLyrics: hasSyncedLyrics)
        updateKeepAlive()
#endif
    }

    /// Drive Mode means "stay awake until toggled off", not only while an
    /// activity is active — pauses of any length (parking, calls, coffee
    /// stops) must survive
    /// without reopening the app, because a suspended app can neither detect
    /// the resume nor re-request the activity from the background. Battery
    /// cost stays opt-in; the CarPlay automation (README) turns Drive Mode
    /// off when leaving the car.
    private func updateKeepAlive() {
#if os(iOS)
        let shouldRun = driveMode && lyricsEnabled
        if shouldRun && !backgroundKeeper.isRunning {
            do {
                try backgroundKeeper.start()
            } catch {
                driveMode = false
                errorMessage = String(localized: "Drive Mode needs location access to stay alive in the background. Allow it for DriveVerse in Settings → Privacy & Security → Location Services.")
            }
        } else if !shouldRun && backgroundKeeper.isRunning {
            backgroundKeeper.stop()
        }
#endif
    }

    private func fetchLyrics(for state: NowPlayingState, forceRefresh: Bool = false) {
        guard lyricsEnabled else { return }
        lyricsTask?.cancel()
        syncEngine.setLyrics([])
        lyricsState = .loading
        currentLyricsSource = nil
        lyricsCandidates = []
        selectedLyricsCandidateID = nil
        isUsingManualLyrics = false

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.lyricsService.lyrics(
                    for: state,
                    displayMode: self.lyricsDisplayMode,
                    forceRefresh: forceRefresh
                )
                guard !Task.isCancelled else { return }
                self.lyricsCandidates = self.lyricsService.lastCandidates
                self.selectedLyricsCandidateID = self.lyricsService.selectedCandidateID
                self.isUsingManualLyrics = self.lyricsService.isUsingManualSelection
                self.applyLyricsContent(result)
            } catch is CancellationError {
                // superseded by a newer track — nothing to do
            } catch {
                guard !Task.isCancelled else { return }
                self.currentLyricsSource = nil
                self.lyricsState = .failed
                Self.log.warning("lyrics fetch failed for \(state.title.prefix(12), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func disableLyrics() {
        lyricsTask?.cancel()
        lyricsTask = nil
        currentSignature = nil
        syncEngine.setLyrics([])
        lyricsState = .idle
        currentLyricsSource = nil
        lyricsCandidates = []
        selectedLyricsCandidateID = nil
        isUsingManualLyrics = false
#if os(iOS)
        liveActivity.holdWhilePaused = false
        Task { await liveActivity.endNow() }
#endif
        updateKeepAlive()
    }

    private func applyLyricsContent(_ result: LyricsContent) {
        switch result {
        case .document(let document):
            currentLyricsSource = document.source
            if document.isSynchronized {
                lyricsState = .synced(document)
                syncEngine.setLyrics(document.lines)
            } else {
                syncEngine.setLyrics([])
                lyricsState = .plain(document)
            }
        case .instrumental:
            syncEngine.setLyrics([])
            currentLyricsSource = nil
            lyricsState = .instrumental
        case .notFound:
            syncEngine.setLyrics([])
            currentLyricsSource = nil
            lyricsState = .notFound
        }
    }
}
