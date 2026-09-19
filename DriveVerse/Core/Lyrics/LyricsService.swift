import Foundation

/// Cache-first lyrics lookup: versioned provider key → structured cache →
/// LRCLIB → provider-neutral document → cache.
final class LyricsService {
    private let client: LRCLIBClient
    private let cache: LyricsCache

    init(client: LRCLIBClient = LRCLIBClient(), cache: LyricsCache = LyricsCache()) {
        self.client = client
        self.cache = cache
    }

    func lyrics(for state: NowPlayingState) async throws -> LyricsContent {
        let trackSignature = LyricsMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        let signature = LyricsCache.key(source: .lrclib, trackSignature: trackSignature)
        if let hit = cache.lookup(signature: signature) {
            return hit
        }
        let fetched = try await client.fetchLyrics(
            title: state.title, artist: state.artist,
            album: state.album, durationMs: state.durationMs
        )
        let content = Self.structure(fetched, source: .lrclib)
        cache.store(content, signature: signature)
        return content
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
