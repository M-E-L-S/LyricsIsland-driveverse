import Testing
import Foundation
@testable import DriveVerse

@Suite struct LyricsCacheTests {
    private func makeCache(now: @escaping () -> Date) -> (LyricsCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("driveverse-cache-\(UUID().uuidString)")
        return (LyricsCache(directory: dir, now: now), dir)
    }

    private func syncedContent(_ original: String = "你好") -> LyricsContent {
        .document(LyricsDocument(
            source: .lrclib,
            timing: .synced,
            lines: [LyricsLine(
                startTimeMs: 1_000,
                endTimeMs: 2_000,
                original: original,
                translation: "Hello"
            )]
        ))
    }

    @Test func structuredDocumentRoundTripPreservesOriginalAndTranslation() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        let content = syncedContent()
        let signature = "lyrics-v\(LyricsDocument.currentFormatVersion)|lrclib|song|artist|40"
        cache.store(content, signature: signature)
        #expect(cache.lookup(signature: signature) == content)
        #expect(cache.lookup(signature: "other|artist|40") == nil)
    }

    @Test func allContentKindsRoundTrip() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        let values: [LyricsContent] = [
            .document(.plain("plain words", source: .lrclib)),
            .instrumental,
            .notFound,
        ]
        for (index, content) in values.enumerated() {
            cache.store(content, signature: "sig-\(index)")
            #expect(cache.lookup(signature: "sig-\(index)") == content)
        }
    }

    @Test func cacheKeyIncludesProviderAndFormatVersion() {
        let key = LyricsCache.key(source: .lrclib, trackSignature: "song|artist|40")
        #expect(key == "lyrics-v\(LyricsDocument.currentFormatVersion)|lrclib|song|artist|40")
    }

    @Test func selectionCacheSeparatesTranslationAndTransliteration() {
        let translation = LyricsCache.selectionKey(
            trackSignature: "song|artist|40",
            secondaryRequirement: .translation
        )
        let transliteration = LyricsCache.selectionKey(
            trackSignature: "song|artist|40",
            secondaryRequirement: .transliteration
        )
        #expect(translation != transliteration)
    }

    @Test func expiresAfterThirtyDays() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let (cache, dir) = makeCache(now: { fakeNow })
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(syncedContent("x"), signature: "sig")
        fakeNow = fakeNow.addingTimeInterval(29 * 24 * 3600)
        #expect(cache.lookup(signature: "sig") == syncedContent("x"))
        fakeNow = fakeNow.addingTimeInterval(2 * 24 * 3600)
        #expect(cache.lookup(signature: "sig") == nil)
    }

    @Test func notFoundExpiresAfterOneDay() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let (cache, dir) = makeCache(now: { fakeNow })
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(.notFound, signature: "sig")
        fakeNow = fakeNow.addingTimeInterval(3600)
        #expect(cache.lookup(signature: "sig") == .notFound)
        fakeNow = fakeNow.addingTimeInterval(24 * 3600)
        #expect(cache.lookup(signature: "sig") == nil)
    }

    @Test func clearRemovesEverything() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(syncedContent("x"), signature: "a")
        cache.store(.document(.plain("y", source: .lrclib)), signature: "b")
        cache.clear()
        #expect(cache.lookup(signature: "a") == nil)
        #expect(cache.lookup(signature: "b") == nil)
        cache.store(syncedContent("z"), signature: "c")
        #expect(cache.lookup(signature: "c") == syncedContent("z"))
    }

    @Test func candidateListAndManualChoiceRoundTrip() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }
        let choice = LyricsCandidateChoice(
            source: .kugou,
            candidateID: "123",
            title: "Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 200_000,
            content: syncedContent("picked"),
            evaluation: LyricsMatchEvaluation(
                titleMatches: true,
                artistsMatch: true,
                albumMatches: true,
                durationErrorMs: 0,
                secondaryMatches: true,
                isWordSynced: false
            )
        )

        cache.storeCandidateChoices([choice], selectedCandidateID: choice.id, signature: "list")
        cache.storeManualSelection(choice, signature: "manual")

        #expect(cache.candidateChoices(signature: "list")?.0 == [choice])
        #expect(cache.candidateChoices(signature: "list")?.1 == choice.id)
        #expect(cache.manualSelection(signature: "manual") == choice)
        cache.remove(signature: "manual")
        #expect(cache.manualSelection(signature: "manual") == nil)
    }
}
