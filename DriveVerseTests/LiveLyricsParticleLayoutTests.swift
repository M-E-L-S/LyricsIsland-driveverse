#if canImport(UIKit)
import UIKit
import Testing
@testable import DriveVerse

@Suite @MainActor struct LiveLyricsParticleLayoutTests {
    private func cloud(_ text: String, width: CGFloat = 300, height: CGFloat = 50,
                       fontSize: CGFloat = 20, rightToLeft: Bool = false,
                       displayScale: CGFloat = 3) -> LiveLyricsParticleCloud {
        LiveLyricsParticleLayout.cloud(
            text: text, size: CGSize(width: width, height: height),
            font: .systemFont(ofSize: fontSize, weight: .bold),
            minimumScale: 0.75, rightToLeft: rightToLeft, displayScale: displayScale
        )
    }

    @Test func sameGlyphsProduceIdenticalHomesEvenAfterCacheEviction() {
        let first = cloud("字形轮廓必须完整保留")
        for index in 0..<8 { _ = cloud("其他歌词 \(index)") }
        let repeated = cloud("字形轮廓必须完整保留")
        #expect(first.points.count == LiveLyricsParticlePhysics.maximumCount)
        #expect(first.points.map(\.position) == repeated.points.map(\.position))
        #expect(first.points.map(\.diameter) == repeated.points.map(\.diameter))
        #expect(first.points.map(\.opacity) == repeated.points.map(\.opacity))
        #expect(first.visibleCount >= LiveLyricsParticlePhysics.minimumCount)
        #expect(first.points.filter { $0.opacity == 1 }.count == first.visibleCount)
    }

    @Test func differentGlyphsAndGeometryRetargetTheSameSortedRankIdentities() {
        let first = cloud("旧句拨散之后再重聚成清晰的歌词")
        let next = cloud("新句", height: 25)
        #expect(first.points.map(\.id) == next.points.map(\.id))
        #expect(first.points.map(\.diameter) == next.points.map(\.diameter))
        #expect(first.points.map(\.position) != next.points.map(\.position))
        for (left, right) in zip(first.points, first.points.dropFirst()) {
            #expect(left.position.x < right.position.x
                || (left.position.x == right.position.x && left.position.y <= right.position.y))
        }
    }

    @Test func wrappingAndTruncationKeepParticlesInTheTwoVisibleRows() {
        let points = cloud(String(repeating: "你好世界", count: 25), width: 110).points
        #expect(!points.isEmpty)
        #expect(points.contains { $0.position.y < 25 })
        #expect(points.contains { $0.position.y > 25 })
        #expect(points.allSatisfy { $0.position.x >= 0 && $0.position.x < 110 && $0.position.y < 50 })
    }

    @Test func rightToLeftGlyphsStayAtTheTrailingSideOfTheCloud() {
        let points = cloud("שלום", rightToLeft: true).points
        #expect(!points.isEmpty)
        #expect(points.allSatisfy { $0.position.x > 150 && $0.position.x < 300 })
    }

    @Test func supportsEmojiAndCombiningCharacters() {
        let points = cloud("👨‍👩‍👧‍👦e\u{301}你").points
        #expect(!points.isEmpty)
        #expect(points.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    @Test func cacheRespectsFontScaleAndGeometryChanges() {
        let text = "粒子在换行时重新聚合成文字"
        let original = cloud(text)
        #expect(original.points.map(\.position) != cloud(text, width: 110).points.map(\.position))
        #expect(original.inkPixelCount != cloud(text, fontSize: 26).inkPixelCount)
        #expect(original.inkPixelCount != cloud("切换到下一行").inkPixelCount)
        #expect(original.scale != cloud(text, displayScale: 2).scale)
        #expect(original.inkPixelCount == cloud(text).inkPixelCount)
    }

    @Test func largeTypeRespectsSamplingAndParticleBudgets() {
        let result = cloud("动态字体也要保留完整轮廓", width: 600, height: 200, fontSize: 80)
        #expect(!result.points.isEmpty)
        #expect(result.points.count == LiveLyricsParticlePhysics.maximumCount)
        #expect(result.visibleCount <= LiveLyricsParticlePhysics.maximumCount)
        #expect(result.inkPixelCount <= 1_000_000)
        #expect(result.points.allSatisfy { $0.diameter > 0 && $0.diameter < 0.8 })
    }

    @Test func emptyInkAndInvalidGeometryHaveNoParticles() {
        #expect(cloud("").points.isEmpty)
        #expect(cloud("   ").points.isEmpty)
        #expect(cloud("你好", width: 0).points.isEmpty)
        #expect(cloud("你好", height: -1).points.isEmpty)
        #expect(cloud("你好", width: .infinity).points.isEmpty)
        #expect(cloud("你好", height: .nan).points.isEmpty)
        #expect(cloud("你好", width: 100_000).points.isEmpty)
        #expect(cloud("你好", displayScale: .nan).points.isEmpty)
    }
}
#endif
