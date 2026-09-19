import Testing
import Foundation
@testable import DriveVerse

@Suite struct WordTimedLyricsParserTests {
    @Test func parsesNeteaseYRCWords() throws {
        let lines = WordTimedLyricsParser.parseYRC(
            "[1000,1000](1000,400,0)你(1400,600,0)好"
        )
        let line = try #require(lines.first)
        #expect(line.startTimeMs == 1_000)
        #expect(line.endTimeMs == 2_000)
        #expect(line.original == "你好")
        #expect(line.words?.map(\.startTimeMs) == [1_000, 1_400])
        #expect(line.words?.map(\.endTimeMs) == [1_400, 2_000])
    }

    @Test func parsesKugouKRCWordsTranslationAndRomanization() throws {
        let languageObject: [String: Any] = [
            "version": 1,
            "content": [
                ["type": 0, "lyricContent": [["ni ", "hao"]]],
                ["type": 1, "lyricContent": [["hello"]]],
            ],
        ]
        let languageData = try JSONSerialization.data(withJSONObject: languageObject)
        let language = languageData.base64EncodedString()
        let raw = "[ti:Song]\n[ar:Artist]\n[al:Album]\n[language:\(language)]\n[1000,1000]<0,400,0>你<400,600,0>好"
        let lines = WordTimedLyricsParser.parseKRC(raw)
        let line = try #require(lines.first)
        #expect(line.original == "你好")
        #expect(line.translation == "hello")
        #expect(line.transliteration == "ni hao")
        #expect(line.words?.map(\.startTimeMs) == [1_000, 1_400])
        #expect(WordTimedLyricsParser.krcMetadata(raw)["al"] == "Album")
    }

    @Test func mergesTranslationByTimestamp() throws {
        let primary = WordTimedLyricsParser.parseYRC(
            "[1000,1000](1000,500,0)Hello(1500,500,0)!"
        )
        let merged = LyricsLineMerger.merge(
            primary: primary,
            translationRaw: "[00:01.00]你好！",
            transliterationRaw: nil
        )
        let first = try #require(merged.first)
        #expect(first.translation == "你好！")
    }
}
