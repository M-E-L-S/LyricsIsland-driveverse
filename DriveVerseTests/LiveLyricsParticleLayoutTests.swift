#if canImport(UIKit)
import UIKit
import Testing
@testable import DriveVerse

@Suite @MainActor struct LiveLyricsParticleLayoutTests {
    private func raster(_ text: String, width: CGFloat = 300, height: CGFloat = 50,
                        fontSize: CGFloat = 20, rightToLeft: Bool = false,
                        displayScale: CGFloat = 3) -> LiveLyricsParticleRaster {
        LiveLyricsParticleLayout.raster(
            text: text, size: CGSize(width: width, height: height),
            font: .systemFont(ofSize: fontSize, weight: .bold),
            minimumScale: 0.75, rightToLeft: rightToLeft, displayScale: displayScale
        )
    }

    @Test func denseSamplingDoesNotDiscardLongLyricStrokes() {
        let first = raster("字形轮廓必须完整保留字形轮廓")
        #expect(first.particleCount > 900)
        #expect(first.scale == 3)
        #expect(!first.tiles.isEmpty)
        #expect(first.tiles.count <= LiveLyricsParticleLayout.maximumTileCount)
        #expect(LiveLyricsParticleLayout.particleDiameter < 0.6)
        #expect(first.tiles.map(\.bounds) == raster("字形轮廓必须完整保留字形轮廓").tiles.map(\.bounds))
        #expect(Set(first.tiles.map(\.id)).count == first.tiles.count)
    }

    @Test func wrappingAndTruncationKeepParticlesInTheTwoVisibleRows() {
        let tiles = raster(String(repeating: "你好世界", count: 25), width: 110).tiles
        #expect(!tiles.isEmpty)
        #expect(tiles.count <= LiveLyricsParticleLayout.maximumTileCount)
        #expect(tiles.contains { $0.bounds.minY < 25 })
        #expect(tiles.contains { $0.bounds.maxY > 25 })
        #expect(tiles.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= 110 && $0.bounds.maxY <= 50 })
    }

    @Test func rightToLeftGlyphsStayAtTheTrailingSideOfTheBitmap() {
        let tiles = raster("שלום", rightToLeft: true).tiles
        #expect(!tiles.isEmpty)
        #expect(tiles.allSatisfy { $0.bounds.minX > 150 && $0.bounds.maxX <= 300 })
    }

    @Test func supportsEmojiAndCombiningCharacters() {
        let tiles = raster("👨‍👩‍👧‍👦e\u{301}你").tiles
        #expect(!tiles.isEmpty)
        #expect(tiles.allSatisfy { $0.bounds.minX.isFinite && $0.bounds.minY.isFinite })
    }

    @Test func layoutCacheRespectsGeometryFontAndTextChanges() {
        let text = "粒子在换行时重新聚合成文字"
        let original = raster(text)
        #expect(original.tiles.map(\.bounds) != raster(text, width: 110).tiles.map(\.bounds))
        #expect(original.inkPixelCount != raster(text, fontSize: 26).inkPixelCount)
        #expect(original.inkPixelCount != raster("切换到下一行").inkPixelCount)
        #expect(original.scale != raster(text, displayScale: 2).scale)
        #expect(original.inkPixelCount == raster(text).inkPixelCount)
    }

    @Test func tilingRetainsEveryAntialiasedInkPixel() throws {
        let result = raster("细小笔画 e\u{301} שלום", width: 310.25)
        var restoredInk = 0
        for tile in result.tiles {
            let image = try #require(tile.image.cgImage)
            let bitmap = try #require(CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            bitmap.interpolationQuality = .none
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
            for y in 0..<image.height {
                for x in 0..<image.width where data[y * bitmap.bytesPerRow + x * 4 + 3] > 0 {
                    restoredInk += 1
                }
            }
        }
        #expect(result.inkPixelCount > 0)
        #expect(restoredInk == result.inkPixelCount)
    }

    @Test func emptyInkAndInvalidGeometryHaveNoParticles() {
        #expect(raster("").tiles.isEmpty)
        #expect(raster("   ").tiles.isEmpty)
        #expect(raster("你好", width: 0).tiles.isEmpty)
        #expect(raster("你好", height: -1).tiles.isEmpty)
        #expect(raster("你好", width: .infinity).tiles.isEmpty)
        #expect(raster("你好", height: .nan).tiles.isEmpty)
        #expect(raster("你好", width: 100_000).tiles.isEmpty)
        #expect(raster("你好", displayScale: .nan).tiles.isEmpty)
    }
}
#endif
