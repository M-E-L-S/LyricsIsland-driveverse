import Testing
@testable import DriveVerse

@Suite struct LyricsSearchEngineTests {
    @Test func stopsInsideFirstSourceOnPerfectMatch() async throws {
        let first = candidate("kg-1", source: .kugou)
        let perfect = candidate("kg-2", source: .kugou)
        let later = candidate("ne-1", source: .netease)
        let kugou = FakeLyricsProvider(
            source: .kugou,
            candidates: [first, perfect],
            contents: [
                "kg-1": document(source: .kugou, translation: nil, wordSynced: true),
                "kg-2": document(source: .kugou, translation: "Hello", wordSynced: true),
            ]
        )
        let netease = FakeLyricsProvider(
            source: .netease,
            candidates: [later],
            contents: ["ne-1": document(source: .netease, translation: "Hello", wordSynced: true)]
        )

        let outcome = try await LyricsSearchEngine(providers: [kugou, netease]).search(
            query: query,
            secondaryRequirement: .translation
        )

        #expect(kugou.fetchedIDs == ["kg-1", "kg-2"])
        #expect(netease.searchCount == 0)
        #expect(outcome.candidates.map(\.candidateID) == ["kg-1", "kg-2"])
        #expect(outcome.selectedCandidateID == "kugou|kg-2")
        guard case .document(let selected) = outcome.content else {
            Issue.record("expected document")
            return
        }
        #expect(selected.source == .kugou)
    }

    @Test func exhaustsThreeCandidatesBeforeChangingSource() async throws {
        let kugouCandidates = (1...4).map { candidate("kg-\($0)", source: .kugou) }
        let neteaseCandidate = candidate("ne-1", source: .netease)
        let kugou = FakeLyricsProvider(
            source: .kugou,
            candidates: kugouCandidates,
            contents: Dictionary(uniqueKeysWithValues: kugouCandidates.map {
                ($0.identifier, document(source: .kugou, translation: nil, wordSynced: true))
            })
        )
        let netease = FakeLyricsProvider(
            source: .netease,
            candidates: [neteaseCandidate],
            contents: ["ne-1": document(source: .netease, translation: "Hello", wordSynced: true)]
        )

        _ = try await LyricsSearchEngine(providers: [kugou, netease]).search(
            query: query,
            secondaryRequirement: .translation
        )

        #expect(kugou.fetchedIDs == ["kg-1", "kg-2", "kg-3"])
        #expect(netease.fetchedIDs == ["ne-1"])
    }

    @Test func fallbackUsesLexicographicFieldOrder() async throws {
        let albumMismatch = LyricsCandidate(
            identifier: "album-mismatch",
            source: .kugou,
            title: "Song",
            artists: ["Artist"],
            album: "Other Album",
            durationMs: 200_000
        )
        let artistMismatch = LyricsCandidate(
            identifier: "artist-mismatch",
            source: .netease,
            title: "Song",
            artists: ["Other Artist"],
            album: "Album",
            durationMs: 200_000
        )
        let kugou = FakeLyricsProvider(
            source: .kugou,
            candidates: [albumMismatch],
            contents: ["album-mismatch": document(source: .kugou, translation: nil, wordSynced: false)]
        )
        let netease = FakeLyricsProvider(
            source: .netease,
            candidates: [artistMismatch],
            contents: ["artist-mismatch": document(source: .netease, translation: "Hello", wordSynced: true)]
        )

        let outcome = try await LyricsSearchEngine(providers: [kugou, netease]).search(
            query: query,
            secondaryRequirement: .translation
        )

        guard case .document(let selected) = outcome.content else {
            Issue.record("expected document")
            return
        }
        // Artist precedes album, auxiliary text, and word timing.
        #expect(selected.source == .kugou)
    }

    @Test func durationErrorsInsideToleranceTieBeforeWordSyncComparison() async throws {
        let wordSynced = LyricsCandidate(
            identifier: "word-synced",
            source: .netease,
            title: "Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 201_500
        )
        let exactLineSynced = LyricsCandidate(
            identifier: "exact-line-synced",
            source: .lrclib,
            title: "Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 200_000
        )
        let netease = FakeLyricsProvider(
            source: .netease,
            candidates: [wordSynced],
            contents: [
                "word-synced": document(source: .netease, translation: nil, wordSynced: true),
            ]
        )
        let lrclib = FakeLyricsProvider(
            source: .lrclib,
            candidates: [exactLineSynced],
            contents: [
                "exact-line-synced": document(source: .lrclib, translation: nil, wordSynced: false),
            ]
        )

        let outcome = try await LyricsSearchEngine(providers: [netease, lrclib]).search(
            query: query,
            secondaryRequirement: .translation
        )

        #expect(outcome.selectedCandidateID == "netease|word-synced")
    }

    @Test func secondarySettingChangesPerfectCandidate() async throws {
        let translationCandidate = candidate("translation", source: .kugou)
        let romanizedCandidate = candidate("romanized", source: .kugou)

        func provider() -> FakeLyricsProvider {
            FakeLyricsProvider(
                source: .kugou,
                candidates: [translationCandidate, romanizedCandidate],
                contents: [
                    "translation": .document(LyricsDocument(
                        source: .kugou,
                        timing: .wordSynced,
                        lines: [LyricsLine(
                            startTimeMs: 0,
                            original: "你",
                            translation: "you",
                            words: [LyricWordTiming(startTimeMs: 0, endTimeMs: 500, original: "你")]
                        )]
                    )),
                    "romanized": .document(LyricsDocument(
                        source: .kugou,
                        timing: .wordSynced,
                        lines: [LyricsLine(
                            startTimeMs: 0,
                            original: "你",
                            transliteration: "ni",
                            words: [LyricWordTiming(startTimeMs: 0, endTimeMs: 500, original: "你")]
                        )]
                    )),
                ]
            )
        }

        let translationOutcome = try await LyricsSearchEngine(providers: [provider()]).search(
            query: query,
            secondaryRequirement: .translation
        )
        let transliterationOutcome = try await LyricsSearchEngine(providers: [provider()]).search(
            query: query,
            secondaryRequirement: .transliteration
        )

        #expect(translationOutcome.attempts.last?.candidateID == "translation")
        #expect(transliterationOutcome.attempts.last?.candidateID == "romanized")
    }

    @Test func providerFailureFallsThroughToNextSource() async throws {
        let fallbackCandidate = candidate("fallback", source: .netease)
        let fallback = FakeLyricsProvider(
            source: .netease,
            candidates: [fallbackCandidate],
            contents: [
                "fallback": document(source: .netease, translation: "Hello", wordSynced: true)
            ]
        )

        let outcome = try await LyricsSearchEngine(
            providers: [FailingLyricsProvider(source: .kugou), fallback]
        ).search(query: query, secondaryRequirement: .translation)

        guard case .document(let selected) = outcome.content else {
            Issue.record("expected fallback document")
            return
        }
        #expect(selected.source == .netease)
        #expect(outcome.attempts.first?.source == .kugou)
    }

    @Test func fetchedKRCMetadataCanCompleteAlbumMatch() {
        let candidateWithoutAlbum = LyricsCandidate(
            identifier: "kg",
            source: .kugou,
            title: "Song",
            artists: ["Artist"],
            album: nil,
            durationMs: 200_000
        )
        let document = LyricsDocument(
            source: .kugou,
            timing: .wordSynced,
            lines: [LyricsLine(
                startTimeMs: 0,
                original: "Hi",
                translation: "你好",
                words: [LyricWordTiming(startTimeMs: 0, endTimeMs: 500, original: "Hi")]
            )],
            trackMetadata: LyricsTrackMetadata(
                title: "Song",
                artists: ["Artist"],
                album: "Album",
                durationMs: 200_000
            )
        )

        let evaluation = LyricsSearchEngine.evaluate(
            candidate: candidateWithoutAlbum,
            document: document,
            query: query,
            secondaryRequirement: .translation
        )
        #expect(evaluation.isPerfect)
    }

    @Test func chineseLyricsDoNotRequireTranslationButStillRequireTransliteration() {
        let chinese = LyricsDocument(
            source: .netease,
            timing: .wordSynced,
            lines: [LyricsLine(
                startTimeMs: 0,
                original: "话总说不清楚该怎么明了",
                words: [LyricWordTiming(
                    startTimeMs: 0, endTimeMs: 1_000,
                    original: "话总说不清楚该怎么明了"
                )]
            )]
        )
        let match = candidate("chinese", source: .netease)

        let translation = LyricsSearchEngine.evaluate(
            candidate: match,
            document: chinese,
            query: query,
            secondaryRequirement: .translation
        )
        let transliteration = LyricsSearchEngine.evaluate(
            candidate: match,
            document: chinese,
            query: query,
            secondaryRequirement: .transliteration
        )

        #expect(translation.secondaryMatches)
        #expect(translation.isPerfect)
        #expect(!transliteration.secondaryMatches)
        #expect(!transliteration.isPerfect)
    }

    @Test func japaneseAndEnglishLyricsStillRequireTranslation() {
        let match = candidate("foreign", source: .netease)
        for original in ["君の名は何ですか", "Tell me why you went away"] {
            let document = LyricsDocument(
                source: .netease,
                timing: .wordSynced,
                lines: [LyricsLine(
                    startTimeMs: 0,
                    original: original,
                    words: [LyricWordTiming(
                        startTimeMs: 0, endTimeMs: 1_000, original: original
                    )]
                )]
            )
            let evaluation = LyricsSearchEngine.evaluate(
                candidate: match,
                document: document,
                query: query,
                secondaryRequirement: .translation
            )
            #expect(!evaluation.secondaryMatches)
        }
    }

    @Test func titleMismatchRetriesWithTitleOnlyAndKeepsQualityRanking() async throws {
        let unrelated = LyricsCandidate(
            identifier: "unrelated",
            source: .kugou,
            title: "Wrong Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 200_000
        )
        let titleOnlyWithoutTranslation = LyricsCandidate(
            identifier: "title-only-incomplete",
            source: .kugou,
            title: "Song",
            artists: ["Platform Artist"],
            album: "Platform Album",
            durationMs: 200_000
        )
        let titleOnlyPerfect = LyricsCandidate(
            identifier: "title-only-perfect",
            source: .kugou,
            title: "Song",
            artists: ["Platform Artist"],
            album: "Platform Album",
            durationMs: 200_000
        )
        let provider = TitleFallbackLyricsProvider(
            primaryCandidates: [unrelated],
            titleOnlyCandidates: [titleOnlyWithoutTranslation, titleOnlyPerfect],
            contents: [
                "unrelated": document(source: .kugou, translation: "Wrong", wordSynced: true),
                "title-only-incomplete": document(source: .kugou, translation: nil, wordSynced: true),
                "title-only-perfect": document(source: .kugou, translation: "Hello", wordSynced: true),
            ]
        )

        let outcome = try await LyricsSearchEngine(providers: [provider]).search(
            query: query,
            secondaryRequirement: .translation
        )

        #expect(provider.queries.count == 2)
        #expect(provider.queries.first?.artists == ["artist"])
        #expect(provider.queries.first?.album == "Album")
        #expect(provider.queries.last?.artists.isEmpty == true)
        #expect(provider.queries.last?.album == nil)
        #expect(provider.queries.last?.durationMs == 200_000)
        #expect(provider.fetchedIDs == [
            "unrelated", "title-only-incomplete", "title-only-perfect",
        ])
        #expect(outcome.attempts.last?.candidateID == "title-only-perfect")
        #expect(outcome.candidates.map(\.candidateID) == [
            "unrelated", "title-only-incomplete", "title-only-perfect",
        ])
        guard case .document(let selected) = outcome.content else {
            Issue.record("expected title-only fallback document")
            return
        }
        #expect(selected.lines.first?.translation == "Hello")
    }

    @Test func titleOnlyFallbackRejectsAnotherFuzzyTitleMismatch() async throws {
        let unrelated = LyricsCandidate(
            identifier: "unrelated",
            source: .kugou,
            title: "Wrong Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 200_000
        )
        let stillUnrelated = LyricsCandidate(
            identifier: "still-unrelated",
            source: .kugou,
            title: "Another Wrong Song",
            artists: ["Platform Artist"],
            album: "Platform Album",
            durationMs: 200_000
        )
        let provider = TitleFallbackLyricsProvider(
            primaryCandidates: [unrelated],
            titleOnlyCandidates: [stillUnrelated],
            contents: [
                "unrelated": document(source: .kugou, translation: "Wrong", wordSynced: true),
                "still-unrelated": document(source: .kugou, translation: "Wrong", wordSynced: true),
            ]
        )

        let outcome = try await LyricsSearchEngine(providers: [provider]).search(
            query: query,
            secondaryRequirement: .translation
        )

        #expect(provider.queries.count == 2)
        #expect(outcome.content == .notFound)
    }

    private var query: LyricsSearchQuery {
        LyricsSearchQuery(title: "Song", artist: "Artist", album: "Album", durationMs: 200_000)
    }

    private func candidate(_ id: String, source: LyricsSource) -> LyricsCandidate {
        LyricsCandidate(
            identifier: id,
            source: source,
            title: "Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 200_000
        )
    }

    private func document(
        source: LyricsSource,
        translation: String?,
        wordSynced: Bool
    ) -> LyricsContent {
        let words = wordSynced
            ? [LyricWordTiming(startTimeMs: 0, endTimeMs: 500, original: "Hi")]
            : nil
        return .document(LyricsDocument(
            source: source,
            timing: wordSynced ? .wordSynced : .synced,
            lines: [LyricsLine(startTimeMs: 0, original: "Hi", translation: translation, words: words)]
        ))
    }
}

private struct FailingLyricsProvider: LyricsProvider {
    enum Failure: Error { case unavailable }
    let source: LyricsSource

    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate] {
        throw Failure.unavailable
    }

    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent {
        .notFound
    }
}

private final class FakeLyricsProvider: LyricsProvider {
    let source: LyricsSource
    let candidates: [LyricsCandidate]
    let contents: [String: LyricsContent]
    private(set) var searchCount = 0
    private(set) var fetchedIDs: [String] = []

    init(source: LyricsSource, candidates: [LyricsCandidate], contents: [String: LyricsContent]) {
        self.source = source
        self.candidates = candidates
        self.contents = contents
    }

    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate] {
        searchCount += 1
        return candidates
    }

    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent {
        fetchedIDs.append(candidate.identifier)
        return contents[candidate.identifier] ?? .notFound
    }
}

private final class TitleFallbackLyricsProvider: LyricsProvider {
    let source: LyricsSource = .kugou
    let primaryCandidates: [LyricsCandidate]
    let titleOnlyCandidates: [LyricsCandidate]
    let contents: [String: LyricsContent]
    private(set) var queries: [LyricsSearchQuery] = []
    private(set) var fetchedIDs: [String] = []

    init(
        primaryCandidates: [LyricsCandidate],
        titleOnlyCandidates: [LyricsCandidate],
        contents: [String: LyricsContent]
    ) {
        self.primaryCandidates = primaryCandidates
        self.titleOnlyCandidates = titleOnlyCandidates
        self.contents = contents
    }

    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate] {
        queries.append(query)
        return query.artists.isEmpty ? titleOnlyCandidates : primaryCandidates
    }

    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent {
        fetchedIDs.append(candidate.identifier)
        return contents[candidate.identifier] ?? .notFound
    }
}
