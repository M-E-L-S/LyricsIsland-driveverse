#if canImport(UIKit)
import UIKit

struct LiveLyricsParticlePoint: Identifiable {
    let id: Int
    let position: CGPoint
    let diameter: CGFloat
    let opacity: Double
}

struct LiveLyricsParticleCloud {
    let points: [LiveLyricsParticlePoint]
    let visibleCount: Int
    let inkPixelCount: Int
    let scale: CGFloat
}

/// Port of MELS particle-object.js sampleImage + buildCloud morph ordering.
/// Weighted glyph sampling is deterministic across archived Activity updates.
/// Stable rank IDs let the system preserve particle positions and velocity.
@MainActor
enum LiveLyricsParticleLayout {
    private static let maximumRasterPixels: CGFloat = 1_000_000
    private static let empty = LiveLyricsParticleCloud(points: [], visibleCount: 0, inkPixelCount: 0, scale: 1)

    private final class Samples: NSObject {
        let cloud: LiveLyricsParticleCloud
        init(_ cloud: LiveLyricsParticleCloud) { self.cloud = cloud }
    }

    private static let cache: NSCache<NSString, Samples> = {
        let cache = NSCache<NSString, Samples>()
        cache.countLimit = 4
        cache.totalCostLimit = 1_000_000
        return cache
    }()

    static func cloud(text: String, size: CGSize, font: UIFont,
                      minimumScale: CGFloat, rightToLeft: Bool,
                      displayScale: CGFloat) -> LiveLyricsParticleCloud {
        guard !text.isEmpty, size.width.isFinite, size.height.isFinite,
              displayScale.isFinite, displayScale > 0,
              size.width > 0, size.height > 0,
              size.width <= 2_048, size.height <= 512 else { return empty }
        var scale = min(3, min(max(1, displayScale),
                              sqrt(maximumRasterPixels / (size.width * size.height))))
        while ceil(size.width * scale) * ceil(size.height * scale) > maximumRasterPixels {
            scale *= 0.99
        }
        let key = "\(text)|\(size.width)|\(size.height)|\(font.fontName)|\(font.pointSize)|\(minimumScale)|\(rightToLeft)|\(scale)" as NSString
        if let samples = cache.object(forKey: key) { return samples.cloud }
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
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = bitmap.data else { return empty }
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
        // Same alpha cutoff and weighted distribution as the homepage sampler.
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
        let count = LiveLyricsParticlePhysics.maximumCount
        let visibleCount = min(count, max(LiveLyricsParticlePhysics.minimumCount,
            Int((totalWeight / 255 * LiveLyricsParticlePhysics.imageDensity).rounded())))
        var positions: [CGPoint] = []
        positions.reserveCapacity(count)
        for index in 0..<count {
            let pick = (Double(index) + LiveLyricsParticlePhysics.randomUnit(index: index, salt: 0))
                / Double(count) * totalWeight
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
        // The site's oldOrder/newOrder match particles by x, then y. Both
        // snapshots use the same rank pool, so native offsets retarget in place.
        positions.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        let points = positions.enumerated().map { rank, position in
            let variance = 1 + LiveLyricsParticlePhysics.sizeVariance
                * (LiveLyricsParticlePhysics.randomUnit(index: rank, salt: 3) - 0.5) * 1.4
            return LiveLyricsParticlePoint(
                id: rank, position: position,
                diameter: CGFloat(LiveLyricsParticlePhysics.diameter * variance),
                opacity: LiveLyricsParticlePhysics.isVisible(rank: rank, count: visibleCount) ? 1 : 0
            )
        }
        let result = LiveLyricsParticleCloud(
            points: points, visibleCount: visibleCount, inkPixelCount: ink.count, scale: scale
        )
        cache.setObject(Samples(result), forKey: key,
                        cost: points.count * MemoryLayout<LiveLyricsParticlePoint>.stride)
        return result
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
