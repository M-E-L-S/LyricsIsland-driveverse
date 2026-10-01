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
        #expect(!first.layers.isEmpty)
        #expect(first.layers.count <= LiveLyricsParticleLayout.maximumLayerCount)
        #expect(LiveLyricsParticleLayout.particleDiameter < 0.6)
        #expect(first.layers.map(\.bounds) == raster("字形轮廓必须完整保留字形轮廓").layers.map(\.bounds))
        #expect(Set(first.layers.map(\.id)).count == first.layers.count)
    }

    @Test func wrappingAndTruncationKeepParticlesInTheTwoVisibleRows() {
        let layers = raster(String(repeating: "你好世界", count: 25), width: 110).layers
        #expect(!layers.isEmpty)
        #expect(layers.count <= LiveLyricsParticleLayout.maximumLayerCount)
        #expect(layers.contains { $0.bounds.minY < 25 })
        #expect(layers.contains { $0.bounds.maxY > 25 })
        #expect(layers.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= 110 && $0.bounds.maxY <= 50 })
    }

    @Test func rightToLeftGlyphsStayAtTheTrailingSideOfTheBitmap() {
        let layers = raster("שלום", rightToLeft: true).layers
        #expect(!layers.isEmpty)
        #expect(layers.allSatisfy { $0.bounds.minX > 150 && $0.bounds.maxX <= 300 })
    }

    @Test func supportsEmojiAndCombiningCharacters() {
        let layers = raster("👨‍👩‍👧‍👦e\u{301}你").layers
        #expect(!layers.isEmpty)
        #expect(layers.allSatisfy { $0.bounds.minX.isFinite && $0.bounds.minY.isFinite })
    }

    @Test func layoutCacheRespectsGeometryFontAndTextChanges() {
        let text = "粒子在换行时重新聚合成文字"
        let original = raster(text)
        #expect(original.layers.map(\.bounds) != raster(text, width: 110).layers.map(\.bounds))
        #expect(original.inkPixelCount != raster(text, fontSize: 26).inkPixelCount)
        #expect(original.inkPixelCount != raster("切换到下一行").inkPixelCount)
        #expect(original.scale != raster(text, displayScale: 2).scale)
        #expect(original.inkPixelCount == raster(text).inkPixelCount)
    }

    @Test func sparseLayersRetainEveryAntialiasedInkPixel() throws {
        let result = raster("细小笔画 e\u{301} שלום", width: 310.25)
        var restoredInk = 0
        for layer in result.layers {
            let image = try #require(layer.image.cgImage)
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

    @Test func movingLayersContainSparseMicrodotsInsteadOfGlyphChunks() throws {
        let result = raster("粒子拨散之后再重聚成清晰的歌词")
        var examined = 0
        for layer in result.layers {
            let image = try #require(layer.image.cgImage)
            guard image.width >= 24, image.height >= 24 else { continue }
            let bitmap = try #require(CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
            var ink = 0
            for y in 0..<image.height {
                for x in 0..<image.width where data[y * bitmap.bytesPerRow + x * 4 + 3] > 0 {
                    ink += 1
                }
            }
            // Each large moving image is mostly empty, with dispersed dots.
            #expect(Double(ink) / Double(image.width * image.height) < 0.4)
            examined += 1
        }
        #expect(examined >= LiveLyricsParticleLayout.groupsPerRegion)
    }

    @Test func largeTypeRespectsCombinedBitmapAndViewBudgets() throws {
        let result = raster("动态字体也要保留完整轮廓", width: 600, height: 200, fontSize: 80)
        #expect(!result.layers.isEmpty)
        #expect(result.layers.count <= LiveLyricsParticleLayout.maximumLayerCount)
        let imagePixels = try result.layers.reduce(0) { sum, layer in
            let image = try #require(layer.image.cgImage)
            return sum + image.width * image.height
        }
        #expect(imagePixels <= LiveLyricsParticleLayout.maximumLayerPixels)
    }

    @Test func emptyInkAndInvalidGeometryHaveNoParticles() {
        #expect(raster("").layers.isEmpty)
        #expect(raster("   ").layers.isEmpty)
        #expect(raster("你好", width: 0).layers.isEmpty)
        #expect(raster("你好", height: -1).layers.isEmpty)
        #expect(raster("你好", width: .infinity).layers.isEmpty)
        #expect(raster("你好", height: .nan).layers.isEmpty)
        #expect(raster("你好", width: 100_000).layers.isEmpty)
        #expect(raster("你好", displayScale: .nan).layers.isEmpty)
    }
}
#endif
