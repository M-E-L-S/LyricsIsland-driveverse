#if canImport(UIKit)
import UIKit

struct LiveLyricsParticleLayer: Identifiable {
    let id: Int
    let bounds: CGRect
    let anchor: CGPoint
    let image: UIImage

    var localBounds: CGRect {
        bounds.offsetBy(dx: -anchor.x, dy: -anchor.y)
    }
}

struct LiveLyricsParticleRaster {
    let layers: [LiveLyricsParticleLayer]
    let particleCount: Int
    let inkPixelCount: Int
    let scale: CGFloat
    let bitmapBytes: Int
}

/// Homepage alpha-weighted sampling and x/y rank matching, batched into 64
/// persistent sprites for WidgetKit. Each sprite follows one sampled home;
/// its internal dots are a bitmap approximation, not individually animated.
@MainActor
enum LiveLyricsParticleLayout {
    static let particleDiameter: CGFloat = 0.64
    // Homepage desktop sample cap; these dots live in 64 bitmaps, not 10000
    // SwiftUI nodes. Dense sampling keeps small white strokes legible.
    static let particleCount = 10_000
    static let maximumLayerCount = 64
    static let maximumLayerPixels = 500_000
    private static let groupsPerRegion = 4
    private static let maximumRasterPixels = CGFloat(maximumLayerPixels / groupsPerRegion)
    private static let empty = LiveLyricsParticleRaster(
        layers: [], particleCount: 0, inkPixelCount: 0, scale: 1, bitmapBytes: 0
    )

    private struct Samples {
        let key: NSString
        let raster: LiveLyricsParticleRaster
    }
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
        // Interleave four moving cohorts per sorted x region, so each sprite
        // contains disconnected dots instead of a solid vertical glyph strip.
        let maximumDiameter = particleDiameter * 1.245
        while ceil(size.width * scale) * ceil(size.height * scale) > maximumRasterPixels
            || (ceil(size.width * scale) * CGFloat(groupsPerRegion)
                + CGFloat(maximumLayerCount) * (ceil(max(maximumDiameter * scale, 1.6)) + 4))
                * ceil(size.height * scale) > CGFloat(maximumLayerPixels) {
            scale *= 0.99
        }
        let key = "\(text)|\(size.width)|\(size.height)|\(font.fontName)|\(font.pointSize)|\(minimumScale)|\(rightToLeft)|\(scale)" as NSString
        if let cached, cached.key == key { return cached.raster }
        cached = nil
        let full = Measurement(text: text, width: size.width, font: font,
                               rightToLeft: rightToLeft, lineLimit: 0)
        let visibleRows = min(2, full.fragments.count)
        guard visibleRows > 0 else { return empty }
        let fullHeight = full.fragments[visibleRows - 1].bounds.maxY
        let needsScaling = full.fragments.count > 2 || fullHeight > size.height + 1
        let fontScale = needsScaling
            ? min(1, max(minimumScale, size.height / max(1, fullHeight))) : 1
        let measured = Measurement(text: text, width: size.width,
                                   font: font.withSize(font.pointSize * fontScale),
                                   rightToLeft: rightToLeft, lineLimit: 2)
        guard !measured.fragments.isEmpty else { return empty }
        let width = Int(ceil(size.width * scale))
        let height = Int(ceil(size.height * scale))
        guard let bitmap = makeBitmap(width: width, height: height),
              let data = bitmap.data else { return empty }
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
        var ink: [Int] = []
        var weights: [Double] = []
        var totalWeight = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bitmap.bytesPerRow + x * 4 + 3]
                guard alpha >= 128 else { continue }
                totalWeight += Double(alpha)
                ink.append(y * width + x)
                weights.append(totalWeight)
            }
        }
        guard !ink.isEmpty else { return empty }
        var positions: [CGPoint] = []
        positions.reserveCapacity(particleCount)
        for index in 0..<particleCount {
            let pick = (Double(index) + LiveLyricsParticlePhysics.randomUnit(index: index, salt: 0))
                / Double(particleCount) * totalWeight
            var low = 0
            var high = weights.count - 1
            while low < high {
                let middle = (low + high) / 2
                if weights[middle] < pick { low = middle + 1 } else { high = middle }
            }
            let pixel = ink[low]
            positions.append(CGPoint(
                x: (CGFloat(pixel % width) + CGFloat(LiveLyricsParticlePhysics.randomUnit(index: index, salt: 1))) / scale,
                y: (CGFloat(pixel / width) + CGFloat(LiveLyricsParticlePhysics.randomUnit(index: index, salt: 2))) / scale
            ))
        }
        positions.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var layers: [LiveLyricsParticleLayer] = []
        var imageCost = 0
        for group in 0..<maximumLayerCount {
            let regions = maximumLayerCount / groupsPerRegion
            let region = group / groupsPerRegion
            let start = region * particleCount / regions
            let end = (region + 1) * particleCount / regions
            let indices = Array(stride(from: start + group % groupsPerRegion,
                                       to: end, by: groupsPerRegion))
            let anchor = positions[indices[indices.count / 2]]
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX: CGFloat = 0
            var maxY: CGFloat = 0
            for index in indices {
                let point = positions[index]
                let radius = diameter(rank: index, scale: scale) / 2
                minX = min(minX, point.x - radius)
                minY = min(minY, point.y - radius)
                maxX = max(maxX, point.x + radius)
                maxY = max(maxY, point.y + radius)
            }
            let left = max(0, Int(floor(minX * scale)) - 1)
            let top = max(0, Int(floor(minY * scale)) - 1)
            let right = min(width, Int(ceil(maxX * scale)) + 1)
            let bottom = min(height, Int(ceil(maxY * scale)) + 1)
            guard right > left, bottom > top,
                  let mask = makeBitmap(width: right - left, height: bottom - top),
                  let maskData = mask.data else { return empty }
            imageCost += mask.bytesPerRow * (bottom - top)
            guard imageCost <= maximumLayerPixels * 4 else { return empty }
            let target = maskData.assumingMemoryBound(to: UInt8.self)
            for index in indices {
                let center = CGPoint(x: positions[index].x * scale,
                                     y: positions[index].y * scale)
                let radius = diameter(rank: index, scale: scale) * scale / 2
                let firstX = max(left, Int(floor(center.x - radius - 0.5)))
                let lastX = min(right - 1, Int(ceil(center.x + radius + 0.5)))
                let firstY = max(top, Int(floor(center.y - radius - 0.5)))
                let lastY = min(bottom - 1, Int(ceil(center.y + radius + 0.5)))
                for y in firstY...lastY {
                    for x in firstX...lastX {
                        // Like the site's settled fragment shader: clip the
                        // entire point footprint to the text alpha threshold.
                        guard pixels[y * bitmap.bytesPerRow + x * 4 + 3] >= 128 else { continue }
                        let dx = CGFloat(x) + 0.5 - center.x
                        let dy = CGFloat(y) + 0.5 - center.y
                        let coverage = min(1, max(0, radius + 0.5 - sqrt(dx * dx + dy * dy)))
                        let value = UInt8((coverage * 255).rounded())
                        let destination = (y - top) * mask.bytesPerRow + (x - left) * 4
                        guard value > target[destination + 3] else { continue }
                        // Pure premultiplied white, without the previous dim
                        // grain multiplier or lyric fade-out/fade-in phases.
                        for channel in 0..<4 { target[destination + channel] = value }
                    }
                }
            }
            guard let image = mask.makeImage() else { return empty }
            layers.append(LiveLyricsParticleLayer(
                id: group,
                bounds: CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                               width: CGFloat(right - left) / scale,
                               height: CGFloat(bottom - top) / scale),
                anchor: anchor,
                image: UIImage(cgImage: image, scale: scale, orientation: .up)
            ))
        }
        let result = LiveLyricsParticleRaster(
            layers: layers, particleCount: particleCount, inkPixelCount: ink.count,
            scale: scale, bitmapBytes: imageCost
        )
        cached = Samples(key: key, raster: result)
        return result
    }

    private static func diameter(rank: Int, scale: CGFloat) -> CGFloat {
        let varied = particleDiameter * CGFloat(1 + 0.35
            * (LiveLyricsParticlePhysics.randomUnit(index: rank, salt: 3) - 0.5) * 1.4)
        // Downsampled large-type rasters still need white particle cores,
        // rather than only faint subpixel antialiasing. Glyph clipping keeps
        // the larger footprints inside the original text contour.
        return max(varied, 1.6 / scale)
    }

    private static func makeBitmap(width: Int, height: Int) -> CGContext? {
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        bitmap.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap
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
