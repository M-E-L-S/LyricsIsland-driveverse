import Foundation

struct LyricsSearchQuery: Equatable {
    let title: String
    let artists: [String]
    let album: String?
    let durationMs: Int?

    init(title: String, artist: String, album: String?, durationMs: Int?) {
        self.title = title
        self.artists = LyricsMatcher.splitArtists(artist)
        self.album = album
        self.durationMs = durationMs
    }

    private init(title: String, artists: [String], album: String?, durationMs: Int?) {
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
    }

    /// Used only after a full-metadata search selects a candidate whose title,
    /// artist, and album all mismatch. Providers then search with the title
    /// alone, while duration and lyric-quality requirements remain unchanged.
    func titleOnly() -> Self {
        Self(title: title, artists: [], album: nil, durationMs: durationMs)
    }
}

struct LyricsCandidate: Equatable {
    let identifier: String
    let source: LyricsSource
    let title: String
    let artists: [String]
    let album: String?
    let durationMs: Int?

    /// Provider-private values such as a Kugou hash/access key. The search
    /// engine never interprets these fields.
    let metadata: [String: String]
    let embeddedResult: LyricsFetchResult?

    init(
        identifier: String,
        source: LyricsSource,
        title: String,
        artists: [String],
        album: String?,
        durationMs: Int?,
        metadata: [String: String] = [:],
        embeddedResult: LyricsFetchResult? = nil
    ) {
        self.identifier = identifier
        self.source = source
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
        self.metadata = metadata
        self.embeddedResult = embeddedResult
    }
}

protocol LyricsProvider {
    var source: LyricsSource { get }

    /// Returns lightweight track metadata. The engine ranks this list, then
    /// lazily fetches full bodies for at most three candidates.
    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate]
    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent
}

enum LyricsSecondaryRequirement: String, Codable, Equatable {
    case none
    case translation
    case transliteration

    init(displayMode: LyricsDisplayMode) {
        switch displayMode {
        case .original:
            self = .none
        case .originalAndTranslation:
            self = .translation
        case .originalAndTransliteration:
            self = .transliteration
        }
    }
}

/// A lexicographic evaluation. This intentionally is not a weighted score:
/// a later attribute can never outweigh an earlier one.
struct LyricsMatchEvaluation: Equatable, Comparable {
    static let perfectDurationToleranceMs = 3_000

    let titleMatches: Bool
    let artistsMatch: Bool
    let albumMatches: Bool
    let durationErrorMs: Int
    let secondaryMatches: Bool
    let isWordSynced: Bool

    var isPerfect: Bool {
        titleMatches
            && artistsMatch
            && albumMatches
            && durationErrorMs <= Self.perfectDurationToleranceMs
            && secondaryMatches
            && isWordSynced
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.titleMatches != rhs.titleMatches { return !lhs.titleMatches }
        if lhs.artistsMatch != rhs.artistsMatch { return !lhs.artistsMatch }
        if lhs.albumMatches != rhs.albumMatches { return !lhs.albumMatches }
        if lhs.durationErrorMs != rhs.durationErrorMs {
            return lhs.durationErrorMs > rhs.durationErrorMs
        }
        if lhs.secondaryMatches != rhs.secondaryMatches { return !lhs.secondaryMatches }
        if lhs.isWordSynced != rhs.isWordSynced { return !lhs.isWordSynced }
        return false
    }
}

struct LyricsMatch {
    let candidate: LyricsCandidate
    let content: LyricsContent
    let evaluation: LyricsMatchEvaluation
}

struct LyricsSearchAttempt: Equatable {
    enum Result: Equatable {
        case candidate(LyricsMatchEvaluation)
        case noLyrics
        case providerFailed(String)
    }

    let source: LyricsSource
    let candidateID: String?
    let result: Result
}

struct LyricsSearchOutcome {
    let content: LyricsContent
    let attempts: [LyricsSearchAttempt]
}

enum LyricsSearchError: Error {
    case allProvidersFailed
}

/// Fixed-order, lazy provider search. Up to three candidates are tried from a
/// provider before the next provider is searched.
struct LyricsSearchEngine {
    static let candidateAttemptLimit = 3
    static let candidateSearchLimit = 20

    let providers: [any LyricsProvider]

    func search(
        query: LyricsSearchQuery,
        secondaryRequirement: LyricsSecondaryRequirement
    ) async throws -> LyricsSearchOutcome {
        let primary = try await searchOnce(
            query: query,
            secondaryRequirement: secondaryRequirement
        )
        guard let evaluation = primary.selectedEvaluation,
              !evaluation.titleMatches,
              !evaluation.artistsMatch,
              !evaluation.albumMatches else {
            return primary.outcome
        }

        let titleOnly = try await searchOnce(
            query: query.titleOnly(),
            secondaryRequirement: secondaryRequirement
        )
        let attempts = primary.outcome.attempts + titleOnly.outcome.attempts
        switch titleOnly.outcome.content {
        case .document(_):
            // Search APIs can return fuzzy results even for a title-only query.
            // Never replace one unrelated lyric with another unrelated lyric.
            guard titleOnly.selectedEvaluation?.titleMatches == true else {
                return LyricsSearchOutcome(content: .notFound, attempts: attempts)
            }
            return LyricsSearchOutcome(content: titleOnly.outcome.content, attempts: attempts)
        case .instrumental:
            return LyricsSearchOutcome(content: .instrumental, attempts: attempts)
        case .notFound:
            return LyricsSearchOutcome(content: .notFound, attempts: attempts)
        }
    }

    private struct SearchPass {
        let outcome: LyricsSearchOutcome
        let selectedEvaluation: LyricsMatchEvaluation?
    }

    private func searchOnce(
        query: LyricsSearchQuery,
        secondaryRequirement: LyricsSecondaryRequirement
    ) async throws -> SearchPass {
        var best: LyricsMatch?
        var attempts: [LyricsSearchAttempt] = []
        var failedProviderCount = 0
        var foundInstrumental = false

        for provider in providers {
            try Task.checkCancellation()

            let candidates: [LyricsCandidate]
            do {
                candidates = try await provider.search(for: query, limit: Self.candidateSearchLimit)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedProviderCount += 1
                attempts.append(LyricsSearchAttempt(
                    source: provider.source,
                    candidateID: nil,
                    result: .providerFailed(String(describing: error))
                ))
                continue
            }

            let ordered = candidates
                .enumerated()
                .sorted { lhs, rhs in
                    let left = Self.metadataEvaluation(candidate: lhs.element, query: query)
                    let right = Self.metadataEvaluation(candidate: rhs.element, query: query)
                    return left == right ? lhs.offset < rhs.offset : left > right
                }
                .map { $0.element }
                .prefix(Self.candidateAttemptLimit)

            for candidate in ordered {
                try Task.checkCancellation()
                do {
                    let content = try await provider.lyrics(for: candidate)
                    switch content {
                    case .document(let document):
                        let evaluation = Self.evaluate(
                            candidate: candidate,
                            document: document,
                            query: query,
                            secondaryRequirement: secondaryRequirement
                        )
                        attempts.append(LyricsSearchAttempt(
                            source: provider.source,
                            candidateID: candidate.identifier,
                            result: .candidate(evaluation)
                        ))
                        let match = LyricsMatch(
                            candidate: candidate,
                            content: content,
                            evaluation: evaluation
                        )
                        if evaluation.isPerfect {
                            return SearchPass(
                                outcome: LyricsSearchOutcome(content: content, attempts: attempts),
                                selectedEvaluation: evaluation
                            )
                        }
                        if best == nil || best!.evaluation < evaluation {
                            best = match
                        }
                    case .instrumental:
                        let metadata = Self.metadataEvaluation(candidate: candidate, query: query)
                        if metadata.titleMatches,
                           metadata.artistsMatch,
                           metadata.albumMatches,
                           metadata.durationErrorMs <= LyricsMatchEvaluation.perfectDurationToleranceMs {
                            foundInstrumental = true
                        }
                        attempts.append(LyricsSearchAttempt(
                            source: provider.source,
                            candidateID: candidate.identifier,
                            result: .noLyrics
                        ))
                    case .notFound:
                        attempts.append(LyricsSearchAttempt(
                            source: provider.source,
                            candidateID: candidate.identifier,
                            result: .noLyrics
                        ))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    attempts.append(LyricsSearchAttempt(
                        source: provider.source,
                        candidateID: candidate.identifier,
                        result: .providerFailed(String(describing: error))
                    ))
                }
            }
        }

        if let best {
            return SearchPass(
                outcome: LyricsSearchOutcome(content: best.content, attempts: attempts),
                selectedEvaluation: best.evaluation
            )
        }
        if foundInstrumental {
            return SearchPass(
                outcome: LyricsSearchOutcome(content: .instrumental, attempts: attempts),
                selectedEvaluation: nil
            )
        }
        if !providers.isEmpty, failedProviderCount == providers.count {
            throw LyricsSearchError.allProvidersFailed
        }
        return SearchPass(
            outcome: LyricsSearchOutcome(content: .notFound, attempts: attempts),
            selectedEvaluation: nil
        )
    }

    static func evaluate(
        candidate: LyricsCandidate,
        document: LyricsDocument,
        query: LyricsSearchQuery,
        secondaryRequirement: LyricsSecondaryRequirement
    ) -> LyricsMatchEvaluation {
        let resolved = document.trackMetadata.map { metadata in
            LyricsCandidate(
                identifier: candidate.identifier,
                source: candidate.source,
                title: metadata.title ?? candidate.title,
                artists: metadata.artists.isEmpty ? candidate.artists : metadata.artists,
                album: metadata.album ?? candidate.album,
                durationMs: metadata.durationMs ?? candidate.durationMs,
                metadata: candidate.metadata,
                embeddedResult: candidate.embeddedResult
            )
        } ?? candidate
        let metadata = metadataEvaluation(candidate: resolved, query: query)
        let secondaryMatches: Bool
        switch secondaryRequirement {
        case .none:
            secondaryMatches = true
        case .translation:
            secondaryMatches = document.lines.contains { $0.translation?.isEmpty == false }
        case .transliteration:
            secondaryMatches = document.lines.contains { $0.transliteration?.isEmpty == false }
        }
        return LyricsMatchEvaluation(
            titleMatches: metadata.titleMatches,
            artistsMatch: metadata.artistsMatch,
            albumMatches: metadata.albumMatches,
            durationErrorMs: metadata.durationErrorMs,
            secondaryMatches: secondaryMatches,
            isWordSynced: document.isWordSynced
        )
    }

    private static func metadataEvaluation(
        candidate: LyricsCandidate,
        query: LyricsSearchQuery
    ) -> LyricsMatchEvaluation {
        let titleMatches = LyricsMatcher.titlesMatch(query.title, candidate.title)
        let artistsMatch = LyricsMatcher.artistsMatch(query.artists, candidate.artists)
        let albumMatches = LyricsMatcher.albumsMatch(query.album, candidate.album)
        let durationError: Int
        if let wanted = query.durationMs, let actual = candidate.durationMs {
            durationError = abs(wanted - actual)
        } else if query.durationMs == nil {
            durationError = 0
        } else {
            durationError = .max
        }
        return LyricsMatchEvaluation(
            titleMatches: titleMatches,
            artistsMatch: artistsMatch,
            albumMatches: albumMatches,
            durationErrorMs: durationError,
            secondaryMatches: false,
            isWordSynced: false
        )
    }
}
