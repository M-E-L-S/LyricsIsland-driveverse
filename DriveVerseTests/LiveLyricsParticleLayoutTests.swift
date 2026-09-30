#if canImport(UIKit)
import UIKit
import Testing
@testable import DriveVerse

@Suite @MainActor struct LiveLyricsParticleLayoutTests {
    private func points(_ text: String, width: CGFloat = 300, height: CGFloat = 50,
                        fontSize: CGFloat = 20, rightToLeft: Bool = false) -> [CGPoint] {
        LiveLyricsParticleLayout.points(
            text: text, size: CGSize(width: width, height: height),
            font: .systemFont(ofSize: fontSize, weight: .bold),
            minimumScale: 0.75, rightToLeft: rightToLeft
        )
    }

    @Test func chineseGlyphsProduceBoundedDeterministicSamples() {
        let first = points("保留现在的逐行歌词效果")
        #expect(!first.isEmpty)
        #expect(first.count <= LiveLyricsParticleLayout.maximumParticleCount)
        #expect(first == points("保留现在的逐行歌词效果"))
        #expect(Set(first.map { "\($0.x),\($0.y)" }).count == first.count)
        #expect(first.allSatisfy { $0.x >= 0 && $0.x < 300 && $0.y >= 0 && $0.y < 50 })
    }

    @Test func wrappingAndTruncationKeepParticlesInTheTwoVisibleRows() {
        let samples = points(String(repeating: "你好世界", count: 25), width: 110)
        #expect(!samples.isEmpty)
        #expect(samples.count <= LiveLyricsParticleLayout.maximumParticleCount)
        #expect(samples.contains { $0.y < 25 })
        #expect(samples.contains { $0.y >= 25 })
        #expect(samples.allSatisfy { $0.x < 110 && $0.y < 50 })
    }

    @Test func rightToLeftGlyphsStayAtTheTrailingSideOfTheBitmap() {
        let samples = points("שלום", rightToLeft: true)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.x > 150 && $0.x < 300 })
    }

    @Test func supportsEmojiAndCombiningCharacters() {
        let samples = points("👨‍👩‍👧‍👦e\u{301}你")
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func layoutCacheRespectsGeometryFontAndTextChanges() {
        let text = "粒子在换行时重新聚合成文字"
        let original = points(text)
        #expect(original != points(text, width: 110))
        #expect(original != points(text, fontSize: 26))
        #expect(original != points("切换到下一行"))
        #expect(original == points(text))
    }

    @Test func emptyInkAndInvalidGeometryHaveNoParticles() {
        #expect(points("").isEmpty)
        #expect(points("   ").isEmpty)
        #expect(points("你好", width: 0).isEmpty)
        #expect(points("你好", height: -1).isEmpty)
        #expect(points("你好", width: .infinity).isEmpty)
        #expect(points("你好", height: .nan).isEmpty)
        #expect(points("你好", width: 100_000).isEmpty)
    }
}
#endif
