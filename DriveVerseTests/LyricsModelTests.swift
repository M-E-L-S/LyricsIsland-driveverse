import Testing
import Foundation
@testable import DriveVerse

@Suite struct LyricsModelTests {
    @Test func serviceStructuringPreservesChineseOriginal() throws {
        let content = LyricsService.structure(
            .synced("[00:01.00]月亮代表我的心"),
            source: .lrclib
        )
        guard case .document(let document) = content else {
            Issue.record("expected a structured lyrics document")
            return
        }
        #expect(document.source == .lrclib)
        #expect(document.formatVersion == LyricsDocument.currentFormatVersion)
        #expect(document.lines.first?.original == "月亮代表我的心")
        #expect(document.lines.first?.transliteration == nil)
    }

    @Test func defaultPresentationShowsOriginalAndTranslation() {
        let line = LyricsLine(
            startTimeMs: 0,
            original: "月亮代表我的心",
            translation: "The moon represents my heart"
        )
        let options = LyricsDisplayOptions()
        #expect(LyricsTextRenderer.primary(for: line, options: options) == "月亮代表我的心")
        #expect(LyricsTextRenderer.secondary(for: line, options: options) == "The moon represents my heart")
    }

    @Test func transliterationIsOptInAndDoesNotMutateOriginal() {
        let line = LyricsLine(startTimeMs: 0, original: "你好")
        let defaultOptions = LyricsDisplayOptions()
        #expect(LyricsTextRenderer.secondary(for: line, options: defaultOptions) == nil)

        let transliterationOptions = LyricsDisplayOptions(
            mode: .originalAndTransliteration,
            chineseConversion: .preserve
        )
        let secondary = LyricsTextRenderer.secondary(for: line, options: transliterationOptions)
        #expect(secondary != nil)
        #expect(line.original == "你好")
        #expect(LyricsTextRenderer.primary(for: line, options: transliterationOptions) == "你好")
    }

    @Test func traditionalAndSimplifiedConversionIsPresentationOnly() {
        let line = LyricsLine(startTimeMs: 0, original: "後臺音樂")
        let options = LyricsDisplayOptions(mode: .original, chineseConversion: .simplified)
        #expect(LyricsTextRenderer.primary(for: line, options: options) == "后台音乐")
        #expect(line.original == "後臺音樂")
    }

    @Test func wordTimingSurvivesCodableRoundTrip() throws {
        let line = LyricsLine(
            startTimeMs: 1_000,
            endTimeMs: 2_000,
            original: "你好",
            words: [LyricWordTiming(startTimeMs: 1_000, endTimeMs: 1_500, original: "你")]
        )
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(LyricsLine.self, from: data)
        #expect(decoded == line)
    }
}
