import Foundation

/// Cache-first multi-provider lookup. Providers are queried in fixed order and
/// each provider's best three metadata candidates are fetched lazily.
final class LyricsService {
    private let searchEngine: LyricsSearchEngine
    private let cache: LyricsCache
    private(set) var lastAttempts: [LyricsSearchAttempt] = []

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
        if !forceRefresh, let hit = cache.lookup(signature: signature) {
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
        cache.store(outcome.content, signature: signature)
        return outcome.content
    }

    func clearCache() {
        cache.clear()
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
