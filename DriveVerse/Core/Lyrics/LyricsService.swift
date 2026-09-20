import Foundation

/// Cache-first multi-provider lookup. Providers are queried in fixed order and
/// each provider's best three metadata candidates are fetched lazily.
final class LyricsService {
    private let searchEngine: LyricsSearchEngine
    private let cache: LyricsCache
    private(set) var lastAttempts: [LyricsSearchAttempt] = []
    private(set) var lastCandidates: [LyricsCandidateChoice] = []
    private(set) var selectedCandidateID: String?
    private(set) var isUsingManualSelection = false

    init(
        providers: [any LyricsProvider] = [
            KugouLyricsProvider(),
            NeteaseLyricsProvider(),
            LRCLIBProvider(),
        ],
        cache: LyricsCache = LyricsCache()
    ) {
        searchEngine = LyricsSearchEngine(providers: providers)
        self.cache = cache
    }

    /// Compatibility initializer retained for focused LRCLIB tests and for
    /// deployments that explicitly disable third-party providers.
    init(client: LRCLIBClient, cache: LyricsCache = LyricsCache()) {
        searchEngine = LyricsSearchEngine(providers: [LRCLIBProvider(client: client)])
        self.cache = cache
    }

    func lyrics(
        for state: NowPlayingState,
        displayMode: LyricsDisplayMode = .originalAndTranslation,
        forceRefresh: Bool = false
    ) async throws -> LyricsContent {
        let trackSignature = LyricsMatcher.signature(
            title: state.title,
            artist: state.artist,
            durationMs: state.durationMs,
            album: state.album
        )
        let requirement = LyricsSecondaryRequirement(displayMode: displayMode)
        let signature = LyricsCache.selectionKey(
            trackSignature: trackSignature,
            secondaryRequirement: requirement
        )
        let candidatesSignature = LyricsCache.candidatesKey(selectionKey: signature)
        let manualSignature = LyricsCache.manualKey(
            trackSignature: trackSignature,
            secondaryRequirement: requirement
        )
        let legacyManualSignature = LyricsCache.legacyManualKey(
            trackSignature: trackSignature,
            secondaryRequirement: requirement
        )
        let manual = cache.manualSelection(signature: manualSignature)
            ?? cache.manualSelection(signature: legacyManualSignature)
        if !forceRefresh, let manual {
            cache.storeManualSelection(manual, signature: manualSignature)
            cache.remove(signature: legacyManualSignature)
            restoreCandidates(from: candidatesSignature)
            selectedCandidateID = manual.id
            isUsingManualSelection = true
            lastAttempts = []
            return manual.content
        }
        if !forceRefresh, let hit = cache.lookup(signature: signature) {
            restoreCandidates(from: candidatesSignature)
            isUsingManualSelection = false
            lastAttempts = []
            return hit
        }

        let outcome = try await searchEngine.search(
            query: LyricsSearchQuery(
                title: state.title,
                artist: state.artist,
                album: state.album,
                durationMs: state.durationMs
            ),
            secondaryRequirement: requirement
        )
        lastAttempts = outcome.attempts
        lastCandidates = outcome.candidates
        selectedCandidateID = outcome.selectedCandidateID
        isUsingManualSelection = false
        cache.store(outcome.content, signature: signature)
        cache.storeCandidateChoices(
            outcome.candidates,
            selectedCandidateID: outcome.selectedCandidateID,
            signature: candidatesSignature
        )
        return outcome.content
    }

    func select(
        _ choice: LyricsCandidateChoice,
        for state: NowPlayingState,
        displayMode: LyricsDisplayMode
    ) {
        let keys = trackAndRequirement(for: state, displayMode: displayMode)
        cache.storeManualSelection(
            choice,
            signature: LyricsCache.manualKey(
                trackSignature: keys.track,
                secondaryRequirement: keys.requirement
            )
        )
        selectedCandidateID = choice.id
        isUsingManualSelection = true
    }

    func useAutomaticSelection(for state: NowPlayingState, displayMode: LyricsDisplayMode) {
        let keys = trackAndRequirement(for: state, displayMode: displayMode)
        cache.remove(signature: LyricsCache.manualKey(
            trackSignature: keys.track,
            secondaryRequirement: keys.requirement
        ))
        cache.remove(signature: LyricsCache.legacyManualKey(
            trackSignature: keys.track,
            secondaryRequirement: keys.requirement
        ))
        isUsingManualSelection = false
    }

    func clearCache() {
        cache.clear()
        lastCandidates = []
        selectedCandidateID = nil
        isUsingManualSelection = false
    }

    private func trackAndRequirement(
        for state: NowPlayingState,
        displayMode: LyricsDisplayMode
    ) -> (track: String, requirement: LyricsSecondaryRequirement) {
        let track = LyricsMatcher.signature(
            title: state.title,
            artist: state.artist,
            durationMs: state.durationMs,
            album: state.album
        )
        return (track, LyricsSecondaryRequirement(displayMode: displayMode))
    }

    private func restoreCandidates(from signature: String) {
        if let cached = cache.candidateChoices(signature: signature) {
            lastCandidates = cached.0
            selectedCandidateID = cached.1
        } else {
            lastCandidates = []
            selectedCandidateID = nil
        }
    }

    static func structure(_ result: LyricsFetchResult, source: LyricsSource) -> LyricsContent {
        switch result {
        case .synced(let raw):
            let lines = LRCParser.parse(raw)
            guard !lines.isEmpty else { return .notFound }
            return .document(LyricsDocument(source: source, timing: .synced, lines: lines))
        case .plain(let text):
            return .document(.plain(text, source: source))
        case .instrumental:
            return .instrumental
        case .notFound:
            return .notFound
        }
    }
}
