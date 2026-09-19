import Testing
@testable import DriveVerse

@Suite struct LyricsMatcherTests {
    @Test func specNormalizationCase() {
        #expect(LyricsMatcher.normalizeTitle("Song (feat. X) - Remix") == "song")
    }

    @Test func remasteredSuffixStripped() {
        #expect(LyricsMatcher.normalizeTitle("Bohemian Rhapsody (Remastered 2011)") == "bohemian rhapsody")
    }

    @Test func dashSuffixStripped() {
        #expect(LyricsMatcher.normalizeTitle("Track - Radio Edit") == "track")
        #expect(LyricsMatcher.normalizeTitle("Heroes - 2017 Remaster") == "heroes")
    }

    @Test func featWithoutParensStripped() {
        #expect(LyricsMatcher.normalizeTitle("Umbrella feat. Jay-Z") == "umbrella")
        #expect(LyricsMatcher.normalizeTitle("Umbrella ft. Jay-Z") == "umbrella")
        #expect(LyricsMatcher.normalizeTitle("Umbrella featuring Jay-Z") == "umbrella")
    }

    @Test func bracketSuffixStripped() {
        #expect(LyricsMatcher.normalizeTitle("Song [Live at Wembley]") == "song")
    }

    @Test func plainTitleUntouched() {
        #expect(LyricsMatcher.normalizeTitle("Yesterday") == "yesterday")
    }

    @Test func wordContainingFtNotMangled() {
        // "soft" contains "ft" — markers require surrounding spaces.
        #expect(LyricsMatcher.normalizeTitle("Soft Spot") == "soft spot")
    }

    @Test func titleMatchPreservesMaterialVersionTerms() {
        #expect(LyricsMatcher.titlesMatch("Song", "Song (Remastered 2011)" ) == false)
        #expect(LyricsMatcher.titlesMatch("Song (Live)", "Song - Live at Wembley"))
    }

    @Test func artistFeatStripped() {
        #expect(LyricsMatcher.normalizeArtist("Rihanna feat. JAY-Z") == "rihanna")
        #expect(LyricsMatcher.normalizeArtist("Calvin Harris (with Dua Lipa)") == "calvin harris")
    }

    @Test func multiArtistSetsMustMatch() {
        #expect(LyricsMatcher.artistsMatch(["Artist A", "Artist B"], ["Artist B & Artist A"]))
        #expect(!LyricsMatcher.artistsMatch(["Artist A"], ["Artist A", "Artist B"]))
    }

    @Test func signatureStableAcrossNonVersionDecorations() {
        let a = LyricsMatcher.signature(title: "Song (feat. Guest)", artist: "Artist", durationMs: 200_000)
        let b = LyricsMatcher.signature(title: "Song", artist: "Artist", durationMs: 201_000)
        #expect(a == b)
    }

    @Test func signatureDiffersForMaterialVersion() {
        let original = LyricsMatcher.signature(title: "Song", artist: "Artist", durationMs: 200_000)
        let remaster = LyricsMatcher.signature(
            title: "Song (Remastered)", artist: "Artist", durationMs: 200_000
        )
        #expect(original != remaster)
    }

    @Test func signatureDiffersByDuration() {
        let a = LyricsMatcher.signature(title: "Song", artist: "Artist", durationMs: 200_000)
        let b = LyricsMatcher.signature(title: "Song", artist: "Artist", durationMs: 260_000)
        #expect(a != b)
    }

    @Test func signatureDiffersByAlbum() {
        let a = LyricsMatcher.signature(
            title: "Song", artist: "Artist", durationMs: 200_000, album: "Album A"
        )
        let b = LyricsMatcher.signature(
            title: "Song", artist: "Artist", durationMs: 200_000, album: "Album B"
        )
        #expect(a != b)
    }

    @Test func signatureWithoutDuration() {
        let s = LyricsMatcher.signature(title: "Song", artist: "Artist", durationMs: nil)
        #expect(s == "song|artist|-1")
    }
}
