#if canImport(UIKit)
import UIKit

struct LiveLyricsParticleLayer: Identifiable {
    let id: Int
    let bounds: CGRect
    let image: UIImage
}

struct LiveLyricsParticleRaster {
    let layers: [LiveLyricsParticleLayer]
    let particleCount: Int
    let inkPixelCount: Int
    let scale: CGFloat
    /// Counts the full retained mask buffers, including cropped-out pixels.
    let bitmapBytes: Int
}

/// Batch fine glyph particles into bounded sparse bitmap layers. WidgetKit
/// archives the whole activity (including the island), so thousands of native
/// particle nodes can stall all presentations. Glyph ink is sampled densely
/// without increasing the native view count or drawing outside its contour.
@MainActor
enum LiveLyricsParticleLayout {
    static let particleSpacing: CGFloat = 0.55
    static let groupsPerRegion = 4
    static let maximumLayerCount = 64
    static let maximumLayerPixels = 500_000
    private static let maximumRasterPixels = CGFloat(maximumLayerPixels / groupsPerRegion)
    private static let empty = LiveLyricsParticleRaster(
        layers: [], particleCount: 0, inkPixelCount: 0, scale: 1, bitmapBytes: 0
    )

    private struct Samples {
        let key: NSString
        let raster: LiveLyricsParticleRaster
    }

    // A single cached raster gives a hard retention bound. NSCache's limits
    // are advisory; no collection of old lyric images should accumulate here.
    private static var cached: Samples?

    static func raster(text: String, size: CGSize, font: UIFont,
                       minimumScale: CGFloat, rightToLeft: Bool,
                       displayScale: CGFloat) -> LiveLyricsParticleRaster {
        guard !text.isEmpty, size.width.isFinite, size.height.isFinite,
              displayScale.isFinite, displayScale > 0,
              size.width > 0, size.height > 0,
              size.width <= 2_048, size.height <= 512 else { return empty }
        var scale = min(3, min(max(1, displayScale),
                              sqrt(maximumRasterPixels / (size.width * size.height))))
        // Pixel rounding must not exceed the combined sparse-image budget.
        while CGFloat(ceil(size.width * scale) * ceil(size.height * scale)) > maximumRasterPixels {
            scale *= 0.99
        }
        let key = "\(text)|\(size.width)|\(size.height)|\(font.fontName)|\(font.pointSize)|\(minimumScale)|\(rightToLeft)|\(scale)" as NSString
        if let cached, cached.key == key { return cached.raster }
        cached = nil

        let full = Measurement(text: text, width: size.width, font: font,
                               rightToLeft: rightToLeft, lineLimit: 0)
        let visibleCount = min(2, full.fragments.count)
        guard visibleCount > 0 else { return empty }
        let fullHeight = full.fragments[visibleCount - 1].bounds.maxY
        let needsScaling = full.fragments.count > 2 || fullHeight > size.height + 1
        let fontScale = needsScaling
            ? min(1, max(minimumScale, size.height / max(1, fullHeight))) : 1
        let measured = Measurement(text: text, width: size.width,
                                   font: font.withSize(font.pointSize * fontScale),
                                   rightToLeft: rightToLeft, lineLimit: 2)
        guard !measured.fragments.isEmpty else { return empty }

        let width = Int(ceil(size.width * scale))
        let height = Int(ceil(size.height * scale))
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = bitmap.data else { return empty }

        // TextKit draws in UIKit's top-left coordinate system.
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(bitmap)
        let rowHeight = size.height / CGFloat(measured.fragments.count)
        for (index, fragment) in measured.fragments.enumerated() {
            measured.manager.drawGlyphs(
                forGlyphRange: fragment.glyphs,
                at: CGPoint(x: 0, y: CGFloat(index) * rowHeight - fragment.bounds.minY)
            )
        }
        UIGraphicsPopContext()

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var particleCount = 0
        for x in stride(from: Double(particleSpacing / 2), to: Double(size.width), by: Double(particleSpacing)) {
            for y in stride(from: Double(particleSpacing / 2), to: Double(size.height), by: Double(particleSpacing)) {
                let px = min(width - 1, Int(x * Double(scale)))
                let py = min(height - 1, Int(y * Double(scale)))
                if pixels[py * bitmap.bytesPerRow + px * 4 + 3] > 0 {
                    particleCount += 1
                }
            }
        }
        // Preserve every original antialiased glyph pixel. Interleaved masks
        // separate subpixel particles without reducing settled text brightness.
        var inkPixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * bitmap.bytesPerRow + x * 4
                let alpha = pixels[index + 3]
                guard alpha > 0 else { continue }
                inkPixelCount += 1
                // Preserve white glyph cores and antialiased edges. Sparse
                // mask assignment below already separates the microdots;
                // multiplying by a grain alpha here made the entire line dim.
                let value = alpha
                // Premultiplied white; never introduce pixels outside glyph ink.
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = value
            }
        }
        // A region contains four interleaved masks of disconnected microdots.
        // Increasing region size limits view count without increasing dot size.
        var side = max(1, Int(ceil(24 * scale)))
        while ((width + side - 1) / side) * ((height + side - 1) / side) * groupsPerRegion > maximumLayerCount {
            side += 1
        }
        let columns = (width + side - 1) / side
        var layers: [LiveLyricsParticleLayer] = []
        var imageCost = 0
        for y in stride(from: 0, to: height, by: side) {
            for x in stride(from: 0, to: width, by: side) {
                let regionWidth = min(side, width - x)
                let regionHeight = min(side, height - y)
                let hasInk = (y..<(y + regionHeight)).contains { row in
                    (x..<(x + regionWidth)).contains { column in
                        pixels[row * bitmap.bytesPerRow + column * 4 + 3] > 0
                    }
                }
                guard hasInk else { continue }
                let masks = (0..<groupsPerRegion).compactMap { _ in
                    CGContext(
                        data: nil, width: regionWidth, height: regionHeight,
                        bitsPerComponent: 8, bytesPerRow: regionWidth * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                            | CGBitmapInfo.byteOrder32Big.rawValue
                    )
                }
                let buffers = masks.compactMap { $0.data?.assumingMemoryBound(to: UInt8.self) }
                guard buffers.count == groupsPerRegion else { return empty }
                for mask in masks {
                    mask.clear(CGRect(x: 0, y: 0, width: regionWidth, height: regionHeight))
                }
                var left = Array(repeating: regionWidth, count: groupsPerRegion)
                var top = Array(repeating: regionHeight, count: groupsPerRegion)
                var right = Array(repeating: -1, count: groupsPerRegion)
                var bottom = Array(repeating: -1, count: groupsPerRegion)
                for row in 0..<regionHeight {
                    for column in 0..<regionWidth {
                        let source = (y + row) * bitmap.bytesPerRow + (x + column) * 4
                        guard pixels[source + 3] > 0 else { continue }
                        let cellX = Int((CGFloat(x + column) + 0.5) / scale / particleSpacing)
                        let cellY = Int((CGFloat(y + row) + 0.5) / scale / particleSpacing)
                        let group = particleGroup(column: cellX, row: cellY)
                        let destination = row * masks[group].bytesPerRow + column * 4
                        for channel in 0..<4 {
                            buffers[group][destination + channel] = pixels[source + channel]
                        }
                        left[group] = min(left[group], column)
                        top[group] = min(top[group], row)
                        right[group] = max(right[group], column)
                        bottom[group] = max(bottom[group], row)
                    }
                }
                for group in 0..<groupsPerRegion where right[group] >= 0 {
                    let cropBounds = CGRect(
                        x: left[group], y: top[group],
                        width: right[group] - left[group] + 1,
                        height: bottom[group] - top[group] + 1
                    )
                    guard let image = masks[group].makeImage(),
                          let crop = image.cropping(to: cropBounds) else { return empty }
                    layers.append(LiveLyricsParticleLayer(
                        id: ((y / side) * columns + x / side) * groupsPerRegion + group,
                        bounds: CGRect(
                            x: (CGFloat(x) + cropBounds.minX) / scale,
                            y: (CGFloat(y) + cropBounds.minY) / scale,
                            width: cropBounds.width / scale, height: cropBounds.height / scale
                        ),
                        image: UIImage(cgImage: crop, scale: scale, orientation: .up)
                    ))
                    // Cropped CGImages may retain the full mask backing store.
                    imageCost += masks[group].bytesPerRow * regionHeight
                }
            }
        }
        guard layers.count <= maximumLayerCount,
              imageCost <= maximumLayerPixels * 4 else { return empty }
        let result = LiveLyricsParticleRaster(
            layers: layers, particleCount: particleCount, inkPixelCount: inkPixelCount,
            scale: scale, bitmapBytes: imageCost
        )
        cached = Samples(key: key, raster: result)
        return result
    }

    static func particleGroup(column: Int, row: Int) -> Int {
        let seed = (UInt64(column) &* 73_856_093) ^ (UInt64(row) &* 19_349_663)
        return Int((seed ^ (seed >> 13)) % UInt64(groupsPerRegion))
    }

    private struct Fragment {
        let bounds: CGRect
        let glyphs: NSRange
    }

    private final class Measurement {
        let manager = NSLayoutManager()
        let container: NSTextContainer
        let storage: NSTextStorage
        var fragments: [Fragment] = []

        init(text: String, width: CGFloat, font: UIFont,
             rightToLeft: Bool, lineLimit: Int) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = rightToLeft ? .right : .left
            paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
            storage = NSTextStorage(string: text, attributes: [
                .font: font, .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ])
            container = NSTextContainer(size: CGSize(width: width,
                                                     height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = lineLimit
            container.lineBreakMode = lineLimit > 0 ? .byTruncatingTail : .byWordWrapping
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
                rect, _, _, glyphs, _ in
                self.fragments.append(Fragment(bounds: rect, glyphs: glyphs))
            }
        }
    }
}
#endif
