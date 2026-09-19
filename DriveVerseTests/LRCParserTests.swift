import Testing
@testable import DriveVerse

private func lyricLine(
    _ start: Int,
    _ original: String,
    end: Int? = nil,
    translation: String? = nil,
    transliteration: String? = nil
) -> LyricsLine {
    LyricsLine(
        startTimeMs: start,
        endTimeMs: end,
        original: original,
        translation: translation,
        transliteration: transliteration
    )
}

@Suite struct LRCParserTests {
    @Test func basicLine() {
        let lines = LRCParser.parse("[00:12.34]Hello world")
        #expect(lines == [lyricLine(12_340, "Hello world")])
    }

    @Test func multipleTagsPerLine() {
        let lines = LRCParser.parse("""
        [00:10.00][00:45.00]Chorus line
        [00:20.00]Verse line
        """)
        #expect(lines == [
            lyricLine(10_000, "Chorus line", end: 20_000),
            lyricLine(20_000, "Verse line", end: 45_000),
            lyricLine(45_000, "Chorus line"),
        ])
    }

    @Test func duplicateTimestampsBecomeStructuredBilingualLine() {
        let lines = LRCParser.parse("""
        [00:05.00]明月几时有
        [00:05.00]When will the moon be clear and bright?
        [00:10.00]把酒问青天
        [00:10.00]With a cup of wine in my hand, I ask the sky.
        """)
        #expect(lines == [
            lyricLine(5_000, "明月几时有", end: 10_000,
                      translation: "When will the moon be clear and bright?"),
            lyricLine(10_000, "把酒问青天",
                      translation: "With a cup of wine in my hand, I ask the sky."),
        ])
        #expect(lines[0].original == "明月几时有")
        #expect(lines[0].transliteration == nil)
    }

    @Test func thirdTimestampVariantIsStoredAsTransliteration() {
        let lines = LRCParser.parse("""
        [00:01.00]你好
        [00:01.00]Hello
        [00:01.00]ni hao
        """)
        #expect(lines == [
            lyricLine(1_000, "你好", translation: "Hello", transliteration: "ni hao")
        ])
    }

    @Test func positiveOffsetShiftsEarlier() {
        let lines = LRCParser.parse("""
        [offset:+1000]
        [00:10.00]Line
        """)
        #expect(lines == [lyricLine(9_000, "Line")])
    }

    @Test func negativeOffsetShiftsLater() {
        let lines = LRCParser.parse("""
        [offset:-500]
        [00:10.00]Line
        """)
        #expect(lines == [lyricLine(10_500, "Line")])
    }

    @Test func offsetClampsAtZero() {
        let lines = LRCParser.parse("""
        [offset:+5000]
        [00:03.00]Early line
        """)
        #expect(lines == [lyricLine(0, "Early line")])
    }

    @Test func offsetClampDoesNotMergeDistinctLinesAsTranslation() {
        let lines = LRCParser.parse("""
        [offset:+5000]
        [00:01.00]First early line
        [00:03.00]Second early line
        """)
        #expect(lines.count == 2)
        #expect(lines.map(\.original) == ["First early line", "Second early line"])
        #expect(lines.allSatisfy { $0.startTimeMs == 0 })
        #expect(lines.allSatisfy { $0.translation == nil })
    }

    @Test func outOfOrderTimestampsAreSortedAndBounded() {
        let lines = LRCParser.parse("""
        [00:30.00]Third
        [00:10.00]First
        [00:20.00]Second
        """)
        #expect(lines.map(\.original) == ["First", "Second", "Third"])
        #expect(lines.map(\.startTimeMs) == [10_000, 20_000, 30_000])
        #expect(lines.map(\.endTimeMs) == [20_000, 30_000, nil])
    }

    @Test func metadataTagsIgnored() {
        let lines = LRCParser.parse("""
        [ar:Queen]
        [ti:Bohemian Rhapsody]
        [al:A Night at the Opera]
        [length:05:55]
        [by:someone]
        [00:01.00]Is this the real life
        """)
        #expect(lines == [lyricLine(1_000, "Is this the real life")])
    }

    @Test func emptyTextLinesStripped() {
        let lines = LRCParser.parse("""
        [00:05.00]
        [00:06.00]
        [00:07.00]Real text
        """)
        #expect(lines == [lyricLine(7_000, "Real text")])
    }

    @Test func fractionalDigitVariants() {
        #expect(LRCParser.parse("[01:02.5]X") == [lyricLine(62_500, "X")])
        #expect(LRCParser.parse("[01:02.50]X") == [lyricLine(62_500, "X")])
        #expect(LRCParser.parse("[01:02.500]X") == [lyricLine(62_500, "X")])
        #expect(LRCParser.parse("[01:02]X") == [lyricLine(62_000, "X")])
    }

    @Test func colonFractionSeparator() {
        #expect(LRCParser.parse("[00:10:50]X") == [lyricLine(10_500, "X")])
    }

    @Test func nonTaggedLinesIgnored() {
        let lines = LRCParser.parse("""
        Just some stray text
        [00:10.00]Actual lyric
        """)
        #expect(lines == [lyricLine(10_000, "Actual lyric")])
    }

    @Test func emptyInput() {
        #expect(LRCParser.parse("") == [])
        #expect(LRCParser.parse("[ar:Nobody]") == [])
    }
}
