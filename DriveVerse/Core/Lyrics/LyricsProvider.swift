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

    /// Used after a full-metadata search fails to match the title. Providers
    /// then search with the title alone, while duration and lyric-quality
    /// requirements remain unchanged.
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
struct LyricsMatchEvaluation: Codable, Equatable, Comparable {
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
        let lhsDurationRank = lhs.durationErrorMs <= Self.perfectDurationToleranceMs
            ? 0 : lhs.durationErrorMs
        let rhsDurationRank = rhs.durationErrorMs <= Self.perfectDurationToleranceMs
            ? 0 : rhs.durationErrorMs
        if lhsDurationRank != rhsDurationRank {
            return lhsDurationRank > rhsDurationRank
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

/// A fully fetched candidate that can be previewed and selected by the user.
/// Only candidates reached by the existing lazy search are recorded; building
/// this list never causes an extra provider request.
struct LyricsCandidateChoice: Codable, Equatable, Identifiable {
    let source: LyricsSource
    let candidateID: String
    let title: String
    let artists: [String]
    let album: String?
    let durationMs: Int?
    let content: LyricsContent
    let evaluation: LyricsMatchEvaluation

    var id: String { "\(source.rawValue)|\(candidateID)" }
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
    let candidates: [LyricsCandidateChoice]
    let selectedCandidateID: String?
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
              !evaluation.titleMatches else {
            return primary.outcome
        }

        let titleOnly = try await searchOnce(
            query: query.titleOnly(),
            secondaryRequirement: secondaryRequirement
        )
        let attempts = primary.outcome.attempts + titleOnly.outcome.attempts
        let candidates = Self.merging(primary.outcome.candidates, titleOnly.outcome.candidates)
        switch titleOnly.outcome.content {
        case .document(_):
            // Search APIs can return fuzzy results even for a title-only query.
            // Never replace one unrelated lyric with another unrelated lyric.
            guard titleOnly.selectedEvaluation?.titleMatches == true else {
                return LyricsSearchOutcome(
                    content: .notFound, attempts: attempts,
                    candidates: candidates, selectedCandidateID: nil
                )
            }
            return LyricsSearchOutcome(
                content: titleOnly.outcome.content, attempts: attempts,
                candidates: candidates,
                selectedCandidateID: titleOnly.outcome.selectedCandidateID
            )
        case .instrumental:
            return LyricsSearchOutcome(
                content: .instrumental, attempts: attempts,
                candidates: candidates, selectedCandidateID: nil
            )
        case .notFound:
            return LyricsSearchOutcome(
                content: .notFound, attempts: attempts,
                candidates: candidates, selectedCandidateID: nil
            )
        }
    }

    private static func merging(
        _ first: [LyricsCandidateChoice],
        _ second: [LyricsCandidateChoice]
    ) -> [LyricsCandidateChoice] {
        var seen = Set(first.map(\.id))
        return first + second.filter { seen.insert($0.id).inserted }
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
        var choices: [LyricsCandidateChoice] = []
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
                        choices.append(LyricsCandidateChoice(
                            source: provider.source,
                            candidateID: candidate.identifier,
                            title: candidate.title,
                            artists: candidate.artists,
                            album: candidate.album,
                            durationMs: candidate.durationMs,
                            content: content,
                            evaluation: evaluation
                        ))
                        let match = LyricsMatch(
                            candidate: candidate,
                            content: content,
                            evaluation: evaluation
                        )
                        if evaluation.isPerfect {
                            return SearchPass(
                                outcome: LyricsSearchOutcome(
                                    content: content, attempts: attempts,
                                    candidates: choices,
                                    selectedCandidateID: choices.last?.id
                                ),
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
                outcome: LyricsSearchOutcome(
                    content: best.content, attempts: attempts,
                    candidates: choices,
                    selectedCandidateID: "\(best.candidate.source.rawValue)|\(best.candidate.identifier)"
                ),
                selectedEvaluation: best.evaluation
            )
        }
        if foundInstrumental {
            return SearchPass(
                outcome: LyricsSearchOutcome(
                    content: .instrumental, attempts: attempts,
                    candidates: choices, selectedCandidateID: nil
                ),
                selectedEvaluation: nil
            )
        }
        if !providers.isEmpty, failedProviderCount == providers.count {
            throw LyricsSearchError.allProvidersFailed
        }
        return SearchPass(
            outcome: LyricsSearchOutcome(
                content: .notFound, attempts: attempts,
                candidates: choices, selectedCandidateID: nil
            ),
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
            // A translation is useful for foreign-language lyrics, but it
            // must not force a Chinese song past an otherwise perfect
            // word-synced match and into later providers.
            secondaryMatches = LyricsLanguageDetector.isChinese(document)
                || document.lines.contains { $0.translation?.isEmpty == false }
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

enum LyricsLanguageDetector {
    /// Conservative script-based detection. Japanese lyrics normally include
    /// kana, while Korean includes Hangul; both explicitly prevent a Chinese
    /// classification even when their text also contains Han characters.
    static func isChinese(_ document: LyricsDocument) -> Bool {
        var han = 0
        var kana = 0
        var hangul = 0
        var latin = 0
        var inspected = 0

        scan: for line in document.lines {
            for scalar in line.original.unicodeScalars {
                guard inspected < 1_000 else { break scan }
                inspected += 1
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                     0x20000...0x2FA1F:
                    han += 1
                case 0x3040...0x30FF, 0x31F0...0x31FF:
                    kana += 1
                case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                    hangul += 1
                case 0x0041...0x005A, 0x0061...0x007A:
                    latin += 1
                default:
                    break
                }
            }
        }

        return han >= 4
            && kana == 0
            && hangul == 0
            && han >= latin
    }
}
