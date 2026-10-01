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

    @Test func denseDotsNeverCreateThousandsOfNativeViews() {
        #expect(LiveLyricsParticleLayout.maximumLayerCount <= 64)
        #expect(LiveLyricsParticleLayout.maximumLayerPixels * 4 <= 2_000_000)
        for index in 0..<12 {
            let result = raster(String(repeating: "细粒子歌词 \(index) ", count: index + 1),
                                width: 330, height: index.isMultiple(of: 2) ? 25 : 52)
            #expect(result.particleCount == 10_000)
            #expect(result.layers.count == 64)
            #expect(result.bitmapBytes <= 2_000_000)
        }
    }

    @Test func newLyricsRetainAllSortedRankIdentitiesAndRetargetHomes() {
        let first = raster("旧句粒子直接移动到新句")
        let next = raster("新的歌词重新排列", height: 25)
        #expect(first.layers.map(\.id) == Array(0..<64))
        #expect(first.layers.map(\.id) == next.layers.map(\.id))
        #expect(first.layers.map(\.anchor) != next.layers.map(\.anchor))
        for (a, b) in zip(first.layers, first.layers.dropFirst()) {
            #expect(a.anchor.x <= b.anchor.x)
        }
        for layer in first.layers {
            #expect(abs(layer.localBounds.minX + layer.anchor.x - layer.bounds.minX) < 0.0001)
            #expect(abs(layer.localBounds.minY + layer.anchor.y - layer.bounds.minY) < 0.0001)
        }
    }

    @Test func sameTextRefreshReusesHomesAndImageResources() {
        let first = raster("相同歌词不要重新启动动画")
        let refresh = raster("相同歌词不要重新启动动画")
        #expect(first.layers.map(\.anchor) == refresh.layers.map(\.anchor))
        for (before, after) in zip(first.layers, refresh.layers) {
            #expect(before.image === after.image)
        }
        _ = raster("让缓存淘汰之前的歌词")
        let rebuilt = raster("相同歌词不要重新启动动画")
        #expect(first.layers.map(\.anchor) == rebuilt.layers.map(\.anchor))
        #expect(first.layers.map(\.bounds) == rebuilt.layers.map(\.bounds))
    }

    @Test func particleBuffersArePureWhiteWithOpaqueCores() throws {
        for result in [raster("纯白微粒保持清晰", height: 25),
                       raster("动态字体的纯白粒子", width: 600, height: 200, fontSize: 80)] {
            var opaquePixels = 0
            var allPixelsAreWhite = true
            for layer in result.layers {
                let image = try #require(layer.image.cgImage)
                let data = try #require(image.dataProvider?.data)
                let bytes = try #require(CFDataGetBytePtr(data))
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let offset = y * image.bytesPerRow + x * 4
                        let alpha = bytes[offset + 3]
                        // Premultiplied RGB equals alpha: no grey/color tint.
                        allPixelsAreWhite = allPixelsAreWhite
                            && bytes[offset] == alpha
                            && bytes[offset + 1] == alpha
                            && bytes[offset + 2] == alpha
                        if alpha == 255 { opaquePixels += 1 }
                    }
                }
            }
            #expect(allPixelsAreWhite)
            #expect(opaquePixels > 100)
        }
        #expect(LiveLyricsParticleLayout.particleDiameter < 0.8)
    }

    @Test func dynamicRowsAndRTLKeepTheOriginalTextGeometry() {
        let twoRows = raster(String(repeating: "你好世界", count: 25), width: 110)
        #expect(twoRows.layers.contains { $0.bounds.maxY > 25 })
        #expect(twoRows.layers.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= 110.001 && $0.bounds.maxY <= 50.001 })
        let rtl = raster("שלום", rightToLeft: true)
        #expect(rtl.layers.allSatisfy { $0.anchor.x > 150 && $0.anchor.x < 300 })
    }

    @Test func largeTypeAndEmojiStayWithinTheBitmapBudget() {
        let cases: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("动态字体也要保留完整轮廓", 600.0, 200.0, 80.0),
            ("极端尺寸也必须保持更新", 2048.0, 512.0, 150.0),
            ("👨‍👩‍👧‍👦e\u{301}你", 300.0, 50.0, 20.0)
        ]
        for (text, width, height, font) in cases {
            let result = raster(text, width: width, height: height, fontSize: font)
            #expect(result.layers.count == 64)
            #expect(result.bitmapBytes <= 2_000_000)
            #expect(result.layers.allSatisfy { $0.anchor.x.isFinite && $0.anchor.y.isFinite })
        }
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
